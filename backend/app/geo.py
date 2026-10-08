"""Small geo helpers: geohash bucketing, distances, and route proximity."""
import math

_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"
EARTH_RADIUS_M = 6_371_000


def geohash(lat: float, lng: float, precision: int = 5) -> str:
    lat_lo, lat_hi, lng_lo, lng_hi = -90.0, 90.0, -180.0, 180.0
    bits, bit_count, even, out = 0, 0, True, []
    while len(out) < precision:
        if even:
            mid = (lng_lo + lng_hi) / 2
            if lng >= mid:
                bits = (bits << 1) | 1
                lng_lo = mid
            else:
                bits <<= 1
                lng_hi = mid
        else:
            mid = (lat_lo + lat_hi) / 2
            if lat >= mid:
                bits = (bits << 1) | 1
                lat_lo = mid
            else:
                bits <<= 1
                lat_hi = mid
        even = not even
        bit_count += 1
        if bit_count == 5:
            out.append(_BASE32[bits])
            bits, bit_count = 0, 0
    return "".join(out)


def cells_covering(lat: float, lng: float, radius_m: float, precision: int = 5) -> set[str]:
    """Geohash cells that cover a circle. Samples a grid finer than one cell."""
    # precision-5 cells are ~4.9 km x 4.9 km; sample every ~2 km
    step_m = 2_000
    dlat = radius_m / 111_320
    dlng = radius_m / (111_320 * max(math.cos(math.radians(lat)), 0.01))
    n = max(1, int(radius_m // step_m) + 1)
    cells = set()
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            cells.add(geohash(lat + dlat * i / n, lng + dlng * j / n, precision))
    return cells


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def distance_to_segment_m(lat, lng, a_lat, a_lng, b_lat, b_lng) -> float:
    """Distance from a point to segment A-B using a local flat projection (fine at city scale)."""
    ref = math.radians((a_lat + b_lat) / 2)

    def xy(la, ln):
        return (math.radians(ln) * math.cos(ref) * EARTH_RADIUS_M, math.radians(la) * EARTH_RADIUS_M)

    px, py = xy(lat, lng)
    ax, ay = xy(a_lat, a_lng)
    bx, by = xy(b_lat, b_lng)
    dx, dy = bx - ax, by - ay
    seg2 = dx * dx + dy * dy
    t = 0.0 if seg2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / seg2))
    cx, cy = ax + t * dx, ay + t * dy
    return math.hypot(px - cx, py - cy)
