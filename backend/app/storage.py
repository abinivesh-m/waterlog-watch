"""DynamoDB (reports) and S3 (photos)."""
import time
import uuid
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

from . import config, geo

_ddb = None
_s3 = None


def table():
    global _ddb
    if _ddb is None:
        _ddb = boto3.resource("dynamodb", region_name=config.AWS_REGION).Table(config.REPORTS_TABLE)
    return _ddb


def s3():
    global _s3
    if _s3 is None:
        _s3 = boto3.client("s3", region_name=config.AWS_REGION)
    return _s3


def reset_clients():  # used by tests
    global _ddb, _s3
    _ddb = _s3 = None


def _to_ddb(value):
    if isinstance(value, float):
        return Decimal(str(value))
    if isinstance(value, dict):
        return {k: _to_ddb(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_to_ddb(v) for v in value]
    return value


def _from_ddb(value):
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    if isinstance(value, dict):
        return {k: _from_ddb(v) for k, v in value.items()}
    if isinstance(value, (list, set)):
        return [_from_ddb(v) for v in value]
    return value


def save_photo(report_id: str, image: bytes, fmt: str) -> str:
    key = f"reports/{report_id}.{fmt}"
    s3().put_object(Bucket=config.PHOTOS_BUCKET, Key=key, Body=image,
                    ContentType=f"image/{fmt}")
    return key


def photo_url(key: str) -> str:
    return s3().generate_presigned_url(
        "get_object", Params={"Bucket": config.PHOTOS_BUCKET, "Key": key}, ExpiresIn=3600)


def new_id() -> str:
    return uuid.uuid4().hex[:12]


def create_report(report_id: str, lat: float, lng: float, assessment: dict, photo_key: str, note: str,
                  device_id: str) -> dict:
    now = int(time.time())
    item = {
        "id": report_id,
        "lat": lat,
        "lng": lng,
        "gh5": geo.geohash(lat, lng, config.GEOHASH_PRECISION),
        "created_at": now,
        "updated_at": now,
        "expires_at": now + config.REPORT_TTL_HOURS * 3600,  # DynamoDB TTL attribute
        "status": "active",
        "note": note[:300],
        "photo_key": photo_key,
        "reporter": device_id[:64],
        "voters": {device_id[:64]},  # reporter can't vote on their own report
        "still_there": 1,  # the reporter counts as the first confirmation
        "cleared": 0,
        **assessment,
    }
    table().put_item(Item=_to_ddb(item))
    return item


def get_report(report_id: str) -> dict | None:
    item = table().get_item(Key={"id": report_id}).get("Item")
    return _from_ddb(item) if item else None


def reports_in_cells(cells: set[str], since: int) -> list[dict]:
    out = []
    for cell in cells:
        kwargs = {"IndexName": "gh5-index",
                  "KeyConditionExpression": Key("gh5").eq(cell) & Key("created_at").gte(since)}
        while True:
            resp = table().query(**kwargs)
            out.extend(_from_ddb(i) for i in resp.get("Items", []))
            if "LastEvaluatedKey" not in resp:
                break
            kwargs["ExclusiveStartKey"] = resp["LastEvaluatedKey"]
    return out


def vote(report_id: str, device_id: str, kind: str) -> dict | None:
    """kind: 'still_there' or 'cleared'. One vote per device per report."""
    now = int(time.time())
    update = f"ADD {kind} :one, voters :dev SET updated_at = :now"
    values = {":one": 1, ":dev": {device_id[:64]}, ":now": now, ":d": device_id[:64]}
    if kind == "still_there":  # confirmations keep the report alive longer
        update += ", expires_at = :exp"
        values[":exp"] = now + config.REPORT_TTL_HOURS * 3600
    try:
        item = table().update_item(
            Key={"id": report_id},
            UpdateExpression=update,
            ConditionExpression="attribute_exists(id) AND (attribute_not_exists(voters) OR NOT contains(voters, :d))",
            ExpressionAttributeValues=values,
            ReturnValues="ALL_NEW",
        )["Attributes"]
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            existing = get_report(report_id)
            if existing is None:
                return None
            existing["already_voted"] = True
            return existing
        raise
    item = _from_ddb(item)
    if (item.get("status") == "active" and item.get("cleared", 0) >= config.CLEARED_VOTES_TO_CLOSE
            and item["cleared"] > item.get("still_there", 0)):
        table().update_item(Key={"id": report_id}, UpdateExpression="SET #s = :c",
                            ExpressionAttributeNames={"#s": "status"},
                            ExpressionAttributeValues={":c": "cleared"})
        item["status"] = "cleared"
    return item
