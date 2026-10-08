"""Waterlog Watch API — crowd-sourced, AI-verified street flooding reports.

AWS: API Gateway + Lambda (this app via Mangum), Amazon Bedrock (photo assessment),
Amazon S3 (photos), Amazon DynamoDB (reports, geohash index, TTL expiry).
"""
import base64
import binascii
import json
import logging
import time

from pathlib import Path

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from . import ai, config, geo, routing, storage

class _JsonFormatter(logging.Formatter):
    """One JSON object per line so CloudWatch Logs Insights can query fields."""
    _skip = set(vars(logging.makeLogRecord({})))

    def format(self, record):
        data = {"level": record.levelname, "msg": record.getMessage()}
        data.update({k: v for k, v in vars(record).items() if k not in self._skip and k != "message"})
        return json.dumps(data, default=str)


log = logging.getLogger("waterlog")
if not log.handlers:
    _h = logging.StreamHandler()
    _h.setFormatter(_JsonFormatter())
    log.addHandler(_h)
log.setLevel(logging.INFO)
log.propagate = False

app = FastAPI(title="Waterlog Watch API", version="1.1.0",
              description="Crowd-sourced, AI-verified street flooding alerts. Built on AWS.")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

PUBLIC_FIELDS = ("id", "lat", "lng", "created_at", "updated_at", "status", "note", "is_waterlogging",
                 "depth", "depth_cm_estimate", "severity", "passable", "hazards", "summary",
                 "summary_local", "still_there", "cleared")


def public(report: dict, origin: tuple[float, float] | None = None) -> dict:
    out = {k: report.get(k) for k in PUBLIC_FIELDS}
    out["photo_url"] = storage.photo_url(report["photo_key"]) if report.get("photo_key") else None
    out["age_minutes"] = max(0, int((time.time() - report["created_at"]) // 60))
    if origin:
        out["distance_m"] = round(geo.haversine_m(origin[0], origin[1], report["lat"], report["lng"]))
    if report.get("already_voted"):
        out["already_voted"] = True
    return out


def _active_near(lat: float, lng: float, radius_m: float) -> list[dict]:
    since = int(time.time()) - config.REPORT_TTL_HOURS * 3600 * 4  # TTL deletion can lag; filter below
    now = int(time.time())
    found = storage.reports_in_cells(geo.cells_covering(lat, lng, radius_m), since)
    return [r for r in found
            if r.get("status") == "active" and r.get("expires_at", 0) > now
            and geo.haversine_m(lat, lng, r["lat"], r["lng"]) <= radius_m]


class ReportIn(BaseModel):
    image_base64: str = Field(..., description="JPEG/PNG/WebP photo, base64")
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)
    note: str = ""
    lang: str = "ta"
    device_id: str = Field(..., min_length=4, max_length=64)


class VoteIn(BaseModel):
    device_id: str = Field(..., min_length=4, max_length=64)
    vote: str = Field(..., pattern="^(still_there|cleared)$")


@app.get("/")
def root():
    return {"service": "Waterlog Watch API", "docs": "/docs", "dashboard": "/dashboard", "health": "/health"}


_DASHBOARD = (Path(__file__).parent / "dashboard.html").read_text(encoding="utf-8")


@app.get("/dashboard", response_class=HTMLResponse, include_in_schema=False)
def dashboard():
    """Live command dashboard for ward officers (map + ranked list). ?lat=&lng=&radius_km="""
    return _DASHBOARD


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/reports", status_code=201)
def create_report(body: ReportIn):
    try:
        image = base64.b64decode(body.image_base64, validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(400, "image_base64 is not valid base64")
    if not image:
        raise HTTPException(400, "Empty image")
    if len(image) > config.MAX_IMAGE_BYTES:
        raise HTTPException(413, "Photo is too large (max 4 MB)")

    try:
        ai.image_format(image)
    except ai.AssessmentError as e:
        raise HTTPException(400, str(e))
    if ai.moderate(image):
        log.info("report_rejected", extra={"reason": "moderation"})
        raise HTTPException(422, "This photo can't be posted publicly. Please photograph the street only.")

    started = time.time()
    try:
        assessment = ai.assess_photo(image, body.note, body.lang)
    except ai.AssessmentError as e:
        msg = str(e)
        raise HTTPException(400 if msg.startswith("Unsupported") else 503, msg)

    log.info("assessed", extra={"ms": int((time.time() - started) * 1000), "severity": assessment["severity"],
                                "flood": assessment["is_waterlogging"]})
    if not assessment["is_waterlogging"]:
        raise HTTPException(422, assessment["summary"] or "This photo doesn't look like a waterlogged street.")

    # One report per spot: if an active report sits within 75 m, count this as a confirmation.
    nearby = sorted(_active_near(body.lat, body.lng, 75),
                    key=lambda r: geo.haversine_m(body.lat, body.lng, r["lat"], r["lng"]))
    if nearby:
        updated = storage.vote(nearby[0]["id"], body.device_id, "still_there") or nearby[0]
        return {"merged_into_existing": True, "report": public(updated, (body.lat, body.lng))}

    report_id = storage.new_id()
    key = storage.save_photo(report_id, image, ai.image_format(image))
    item = storage.create_report(report_id, body.lat, body.lng, assessment, photo_key=key,
                                 note=body.note, device_id=body.device_id)
    return {"merged_into_existing": False, "report": public(item, (body.lat, body.lng))}


@app.get("/reports/nearby")
def nearby(lat: float = Query(..., ge=-90, le=90), lng: float = Query(..., ge=-180, le=180),
           radius_km: float = Query(5, gt=0, le=25)):
    reports = _active_near(lat, lng, radius_km * 1000)
    reports.sort(key=lambda r: (-r.get("severity", 0), geo.haversine_m(lat, lng, r["lat"], r["lng"])))
    return {"count": len(reports), "reports": [public(r, (lat, lng)) for r in reports]}


@app.get("/reports/{report_id}")
def get_one(report_id: str):
    r = storage.get_report(report_id)
    if not r:
        raise HTTPException(404, "Report not found")
    return public(r)


@app.post("/reports/{report_id}/vote")
def vote(report_id: str, body: VoteIn):
    r = storage.vote(report_id, body.device_id, body.vote)
    if r is None:
        raise HTTPException(404, "Report not found")
    return public(r)


PASS_KEY = {"car": "car", "scooter": "two_wheeler", "pedestrian": "pedestrian"}


@app.get("/route-check")
def route_check(from_lat: float = Query(..., ge=-90, le=90), from_lng: float = Query(..., ge=-180, le=180),
                to_lat: float = Query(..., ge=-90, le=90), to_lng: float = Query(..., ge=-180, le=180),
                mode: str = Query("car", pattern="^(car|scooter|pedestrian)$"),
                buffer_m: float = Query(60, gt=0, le=500)):
    """Real road route (Amazon Location Service) checked against every active flood report on it.

    A spot counts as "on route" if it is within buffer_m of the road path. The verdict is
    mode-aware: a knee-deep spot blocks a scooter but not necessarily a car.
    """
    if geo.haversine_m(from_lat, from_lng, to_lat, to_lng) > 40_000:
        raise HTTPException(400, "Route check supports trips up to 40 km")
    route = routing.road_route(from_lat, from_lng, to_lat, to_lng, mode)
    path = route["path"]

    # Only query geohash cells along the path (sampled about every 1.5 km), not a giant circle.
    cells, walked = set(), 0.0
    cells |= geo.cells_covering(path[0][0], path[0][1], buffer_m + 500)
    for i in range(1, len(path)):
        walked += geo.haversine_m(path[i - 1][0], path[i - 1][1], path[i][0], path[i][1])
        if walked >= 1500 or i == len(path) - 1:
            cells |= geo.cells_covering(path[i][0], path[i][1], buffer_m + 500)
            walked = 0.0
    now = int(time.time())
    candidates = [r for r in storage.reports_in_cells(cells, now - config.REPORT_TTL_HOURS * 3600 * 4)
                  if r.get("status") == "active" and r.get("expires_at", 0) > now]

    on_route = []
    for r in candidates:
        off, seg = routing.distance_to_path_m(r["lat"], r["lng"], path)
        if off <= buffer_m:
            item = public(r, (from_lat, from_lng))
            item["distance_m"] = round(routing.distance_along_m(path, seg)
                                       + geo.haversine_m(path[seg][0], path[seg][1], r["lat"], r["lng"]))
            item["off_route_m"] = round(off)
            item["blocks_mode"] = not (r.get("passable") or {}).get(PASS_KEY[mode], True)
            on_route.append(item)
    on_route.sort(key=lambda x: x["distance_m"])

    worst = max((x["severity"] for x in on_route), default=0)
    blocked = sum(1 for x in on_route if x["blocks_mode"])
    if blocked or worst >= 4:
        verdict, advice = "avoid", "Flooding on this route is not passable for you. Take another road or wait."
    elif worst == 3:
        verdict, advice = "caution", "Waterlogging on this route. Go slowly and watch for open drains."
    elif worst:
        verdict, advice = "minor", "Minor water on this route. Drive slowly."
    else:
        verdict, advice = "clear", "No waterlogging reported on this route."
    return {"verdict": verdict, "advice": advice, "worst_severity": worst, "blocked_spots": blocked,
            "mode": mode, "route_length_m": route["distance_m"], "duration_s": route["duration_s"],
            "routing_source": route["source"], "path": path, "spots": on_route}


@app.get("/stats")
def stats(lat: float, lng: float, radius_km: float = Query(10, gt=0, le=25)):
    reports = _active_near(lat, lng, radius_km * 1000)
    by_sev = {str(s): 0 for s in range(1, 6)}
    for r in reports:
        by_sev[str(r.get("severity", 1))] += 1
    return {"active_reports": len(reports), "by_severity": by_sev,
            "impassable_for_cars": sum(1 for r in reports if not r.get("passable", {}).get("car", True)),
            "confirmations": sum(r.get("still_there", 0) for r in reports)}
