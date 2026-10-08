"""Real road routes from Amazon Location Service (Routes API v2), with a straight-line fallback."""
import logging

import boto3

from . import config, geo

log = logging.getLogger("waterlog")

MODES = {"car": "Car", "scooter": "Scooter", "pedestrian": "Pedestrian"}
MAX_POINTS = 400

_client = None


def _routes():
    global _client
    if _client is None:
        _client = boto3.client("geo-routes", region_name=config.AWS_REGION)
    return _client


def _thin(points: list, limit: int = MAX_POINTS) -> list:
    if len(points) <= limit:
        return points
    step = len(points) / (limit - 1)
    out = [points[int(i * step)] for i in range(limit - 1)]
    out.append(points[-1])
    return out


def road_route(from_lat: float, from_lng: float, to_lat: float, to_lng: float, mode: str = "car") -> dict:
    """Returns {path: [[lat, lng], ...], distance_m, duration_s, source}. Never raises."""
    try:
        resp = _routes().calculate_routes(
            Origin=[from_lng, from_lat],          # Amazon Location uses [longitude, latitude]
            Destination=[to_lng, to_lat],
            TravelMode=MODES.get(mode, "Car"),
            LegGeometryFormat="Simple",
            OptimizeRoutingFor="FastestRoute",
        )
        route = resp["Routes"][0]
        path = []
        for leg in route.get("Legs", []):
            for lng, lat in leg.get("Geometry", {}).get("LineString", []):
                path.append([lat, lng])
        if len(path) < 2:
            raise ValueError("route has no geometry")
        summary = route.get("Summary", {})
        return {"path": _thin(path), "distance_m": int(summary.get("Distance", 0)),
                "duration_s": int(summary.get("Duration", 0)), "source": "amazon-location"}
    except Exception as e:  # noqa: BLE001 -- fall back so route check always answers
        log.warning("routing_fallback", extra={"error": e.__class__.__name__})
        return {"path": [[from_lat, from_lng], [to_lat, to_lng]],
                "distance_m": round(geo.haversine_m(from_lat, from_lng, to_lat, to_lng)),
                "duration_s": None, "source": "straight-line"}


def distance_to_path_m(lat: float, lng: float, path: list) -> tuple[float, int]:
    """Shortest distance from a point to a polyline, and the index of the nearest segment."""
    best, best_i = float("inf"), 0
    for i in range(len(path) - 1):
        d = geo.distance_to_segment_m(lat, lng, path[i][0], path[i][1], path[i + 1][0], path[i + 1][1])
        if d < best:
            best, best_i = d, i
    return best, best_i


def distance_along_m(path: list, upto_index: int) -> float:
    """Road distance from the start of the path to the start of segment [upto_index]."""
    return sum(geo.haversine_m(path[i][0], path[i][1], path[i + 1][0], path[i + 1][1]) for i in range(upto_index))
