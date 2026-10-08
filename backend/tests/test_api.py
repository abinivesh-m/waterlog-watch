import base64
import os

import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws

os.environ.update(AWS_DEFAULT_REGION="ap-south-1", AWS_REGION="ap-south-1",
                  AWS_ACCESS_KEY_ID="test", AWS_SECRET_ACCESS_KEY="test",
                  REPORTS_TABLE="t-reports", PHOTOS_BUCKET="t-photos")

from app import ai, geo, main, storage  # noqa: E402

JPEG = b"\xff\xd8\xff\xe0" + b"0" * 200
B64 = base64.b64encode(JPEG).decode()

KNEE = {"is_waterlogging": True, "depth": "knee", "depth_cm_estimate": 45, "severity": 4,
        "passable": {"pedestrian": False, "two_wheeler": False, "car": True},
        "hazards": ["open drain risk"], "summary": "Knee-deep water.", "summary_local": "முழங்கால் அளவு தண்ணீர்."}

# Chennai: T. Nagar and two nearby points
TNAGAR = (13.0418, 80.2341)
NEAR_TNAGAR = (13.0420, 80.2343)   # ~30 m away -> merges
GUINDY = (13.0067, 80.2206)        # ~4 km south


@pytest.fixture
def client(monkeypatch):
    with mock_aws():
        ddb = boto3.client("dynamodb", region_name="ap-south-1")
        ddb.create_table(
            TableName="t-reports", BillingMode="PAY_PER_REQUEST",
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"},
                                  {"AttributeName": "gh5", "AttributeType": "S"},
                                  {"AttributeName": "created_at", "AttributeType": "N"}],
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            GlobalSecondaryIndexes=[{"IndexName": "gh5-index",
                                     "KeySchema": [{"AttributeName": "gh5", "KeyType": "HASH"},
                                                   {"AttributeName": "created_at", "KeyType": "RANGE"}],
                                     "Projection": {"ProjectionType": "ALL"}}])
        boto3.client("s3", region_name="ap-south-1").create_bucket(
            Bucket="t-photos", CreateBucketConfiguration={"LocationConstraint": "ap-south-1"})
        storage.reset_clients()
        monkeypatch.setattr(main.config, "REPORTS_TABLE", "t-reports")
        monkeypatch.setattr(main.config, "PHOTOS_BUCKET", "t-photos")
        monkeypatch.setattr(ai, "assess_photo", lambda img, note="", lang="ta": ai.normalise(dict(KNEE)))
        yield TestClient(main.app)
        storage.reset_clients()


def post(client, at, device="dev-1"):
    return client.post("/reports", json={"image_base64": B64, "lat": at[0], "lng": at[1],
                                         "note": "near bus stop", "device_id": device})


def test_create_and_nearby(client):
    r = post(client, TNAGAR)
    assert r.status_code == 201, r.text
    rep = r.json()["report"]
    assert rep["severity"] == 4 and rep["depth"] == "knee" and rep["photo_url"].startswith("https://")
    near = client.get("/reports/nearby", params={"lat": TNAGAR[0], "lng": TNAGAR[1], "radius_km": 2}).json()
    assert near["count"] == 1 and near["reports"][0]["distance_m"] == 0
    far = client.get("/reports/nearby", params={"lat": 12.9, "lng": 80.1, "radius_km": 2}).json()
    assert far["count"] == 0


def test_duplicate_spot_merges(client):
    first = post(client, TNAGAR, "dev-1").json()["report"]
    second = post(client, NEAR_TNAGAR, "dev-2").json()
    assert second["merged_into_existing"] is True
    assert second["report"]["id"] == first["id"] and second["report"]["still_there"] == 2


def test_not_waterlogging_rejected(client, monkeypatch):
    monkeypatch.setattr(ai, "assess_photo",
                        lambda *a, **k: ai.normalise({"is_waterlogging": False, "summary": "This is a selfie."}))
    r = post(client, TNAGAR)
    assert r.status_code == 422 and "selfie" in r.json()["detail"]


def test_votes_clear_report(client):
    rid = post(client, TNAGAR, "dev-1").json()["report"]["id"]
    dup = client.post(f"/reports/{rid}/vote", json={"device_id": "dev-1", "vote": "cleared"}).json()
    assert dup["already_voted"] is True
    for d in ("dev-a", "dev-b", "dev-c"):
        out = client.post(f"/reports/{rid}/vote", json={"device_id": d, "vote": "cleared"}).json()
    assert out["cleared"] == 3 and out["status"] == "cleared"
    assert client.get("/reports/nearby", params={"lat": TNAGAR[0], "lng": TNAGAR[1]}).json()["count"] == 0
    assert client.post("/reports/nope/vote", json={"device_id": "dev-x", "vote": "cleared"}).status_code == 404


def test_route_check(client):
    post(client, TNAGAR)
    on = client.get("/route-check", params={"from_lat": 13.06, "from_lng": 80.24,
                                            "to_lat": GUINDY[0], "to_lng": GUINDY[1]}).json()
    assert on["verdict"] == "avoid" and len(on["spots"]) == 1
    off = client.get("/route-check", params={"from_lat": 13.08, "from_lng": 80.27,
                                             "to_lat": 13.09, "to_lng": 80.28}).json()
    assert off["verdict"] == "clear" and off["spots"] == []


def test_bad_inputs(client):
    assert client.post("/reports", json={"image_base64": "%%%", "lat": 1, "lng": 1,
                                         "device_id": "dev-1"}).status_code == 400
    assert client.post("/reports", json={"image_base64": B64, "lat": 100, "lng": 1,
                                         "device_id": "dev-1"}).status_code == 422
    assert client.get("/stats", params={"lat": TNAGAR[0], "lng": TNAGAR[1]}).json()["active_reports"] == 0


def test_normalise_and_json_extraction():
    raw = 'Sure!\n```json\n{"is_waterlogging": true, "depth": "Waist", "severity": 9, // comment\n "hazards": []}\n```'
    n = ai.normalise(ai._extract_json(raw))
    assert n["depth"] == "waist" and n["severity"] == 5 and n["passable"]["two_wheeler"] is False


def test_geo():
    assert geo.geohash(13.0418, 80.2341, 5) == geo.geohash(13.0420, 80.2343, 5)
    assert 3500 < geo.haversine_m(*TNAGAR, *GUINDY) < 4500
    assert geo.geohash(*TNAGAR, 5) in geo.cells_covering(*TNAGAR, 3000)
