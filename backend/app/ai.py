"""Photo assessment with Amazon Bedrock (Converse API, multimodal).

If Bedrock is unavailable (for example while a new AWS account is still being verified)
and GEMINI_API_KEY is set, the same prompt is sent to Google Gemini instead, so the app
keeps working. Every assessment records which provider produced it.
"""
import base64
import json
import logging
import re
import urllib.error
import urllib.request

import boto3

from . import config

LANG_NAMES = {"en": "English", "ta": "Tamil", "hi": "Hindi", "te": "Telugu", "kn": "Kannada", "ml": "Malayalam"}
DEPTHS = ["none", "ankle", "knee", "waist", "above_waist"]

PROMPT = """You are a flood-safety assessor for Indian city streets.
Look at the photo and judge street waterlogging. Reply with ONLY a JSON object, no prose:
{{
  "is_waterlogging": true or false,        // false if the photo does not show a flooded/waterlogged street or area
  "depth": "none" | "ankle" | "knee" | "waist" | "above_waist",
  "depth_cm_estimate": integer,           // best estimate of standing water depth in cm
  "severity": integer 1-5,                // 1 = puddles, 3 = vehicles struggle, 5 = dangerous/impassable
  "passable": {{"pedestrian": bool, "two_wheeler": bool, "car": bool}},
  "hazards": [short strings],             // e.g. "open drain risk", "fallen tree", "electric pole in water", "fast current"
  "summary": "one sentence in English for commuters",
  "summary_local": "the same sentence in {lang_name}"
}}
Use visual cues: kerbs, tyres, people's legs, vehicle wheels. Be conservative about safety.
User's note (may be empty): {note}"""


class AssessmentError(Exception):
    pass


log = logging.getLogger("waterlog")

_client = None
_rekognition = None

# Rekognition top-level moderation categories that block a public report.
BLOCKED_CATEGORIES = {"Explicit", "Explicit Nudity", "Non-Explicit Nudity of Intimate parts and Kissing",
                      "Violence", "Visually Disturbing", "Hate Symbols"}


def _bedrock():
    global _client
    if _client is None:
        _client = boto3.client("bedrock-runtime", region_name=config.BEDROCK_REGION)
    return _client


def moderate(image: bytes) -> list[str]:
    """Amazon Rekognition content moderation. Returns blocking labels (empty list = OK).

    Fails open: if Rekognition is unavailable the report still goes through Bedrock,
    which rejects anything that isn't a flooded street anyway.
    """
    global _rekognition
    if image_format(image) not in ("jpeg", "png"):  # Rekognition doesn't take WebP
        return []
    try:
        if _rekognition is None:
            _rekognition = boto3.client("rekognition", region_name=config.AWS_REGION)
        labels = _rekognition.detect_moderation_labels(Image={"Bytes": image}, MinConfidence=80)
    except Exception:  # noqa: BLE001
        return []
    found = set()
    for label in labels.get("ModerationLabels", []):
        top = label.get("ParentName") or label.get("Name", "")
        if top in BLOCKED_CATEGORIES or label.get("Name") in BLOCKED_CATEGORIES:
            found.add(top or label.get("Name"))
    return sorted(found)


def image_format(data: bytes) -> str:
    if data[:3] == b"\xff\xd8\xff":
        return "jpeg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    raise AssessmentError("Unsupported image type. Use JPEG, PNG or WebP.")


def _extract_json(text: str) -> dict:
    match = re.search(r"\{.*\}", text, re.S)
    if not match:
        raise AssessmentError("AI response had no JSON")
    raw = re.sub(r"//[^\n]*", "", match.group(0))  # tolerate copied comments
    return json.loads(raw)


def normalise(result: dict) -> dict:
    depth = str(result.get("depth", "none")).lower().replace(" ", "_")
    if depth not in DEPTHS:
        depth = "none"
    try:
        severity = int(result.get("severity", 1))
    except (TypeError, ValueError):
        severity = 1
    severity = max(1, min(5, severity))
    passable = result.get("passable") or {}
    try:
        depth_cm = max(0, int(result.get("depth_cm_estimate", 0)))
    except (TypeError, ValueError):
        depth_cm = 0
    return {
        "is_waterlogging": bool(result.get("is_waterlogging", False)),
        "depth": depth,
        "depth_cm_estimate": depth_cm,
        "severity": severity,
        "passable": {
            "pedestrian": bool(passable.get("pedestrian", severity <= 3)),
            "two_wheeler": bool(passable.get("two_wheeler", severity <= 2)),
            "car": bool(passable.get("car", severity <= 3)),
        },
        "hazards": [str(h)[:80] for h in (result.get("hazards") or [])][:6],
        "summary": str(result.get("summary", ""))[:300],
        "summary_local": str(result.get("summary_local", ""))[:400],
    }


def _assess_bedrock(image: bytes, fmt: str, prompt: str) -> dict:
    resp = _bedrock().converse(
        modelId=config.BEDROCK_MODEL_ID,
        messages=[{"role": "user", "content": [
            {"image": {"format": fmt, "source": {"bytes": image}}},
            {"text": prompt},
        ]}],
        inferenceConfig={"maxTokens": 600, "temperature": 0.1},
    )
    text = "".join(c.get("text", "") for c in resp["output"]["message"]["content"])
    return normalise(_extract_json(text))


def _assess_gemini(image: bytes, fmt: str, prompt: str) -> dict:
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{config.GEMINI_MODEL}:generateContent"
    body = {
        "contents": [{"parts": [
            {"inline_data": {"mime_type": f"image/{fmt}", "data": base64.b64encode(image).decode()}},
            {"text": prompt},
        ]}],
        "generationConfig": {"temperature": 0.1, "maxOutputTokens": 600, "responseMimeType": "application/json"},
    }
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST", headers={
        "Content-Type": "application/json", "x-goog-api-key": config.GEMINI_API_KEY})
    with urllib.request.urlopen(req, timeout=20) as r:
        data = json.loads(r.read())
    text = "".join(p.get("text", "") for p in data["candidates"][0]["content"]["parts"])
    return normalise(_extract_json(text))


def assess_photo(image: bytes, note: str = "", lang: str = "ta") -> dict:
    fmt = image_format(image)
    prompt = PROMPT.format(lang_name=LANG_NAMES.get(lang, "Tamil"), note=note[:300] or "(none)")
    try:
        result = _assess_bedrock(image, fmt, prompt)
        result["ai_provider"] = "amazon-bedrock"
        return result
    except AssessmentError:
        raise
    except Exception as e:  # noqa: BLE001
        bedrock_error = e.__class__.__name__
        log.warning("bedrock_unavailable", extra={"error": bedrock_error, "detail": str(e)[:200]})

    if not config.GEMINI_API_KEY:
        raise AssessmentError(f"Bedrock call failed: {bedrock_error}")
    try:
        result = _assess_gemini(image, fmt, prompt)
        result["ai_provider"] = "gemini-fallback"
        return result
    except AssessmentError:
        raise
    except Exception as e:  # noqa: BLE001
        detail = e.read()[:200].decode(errors="ignore") if isinstance(e, urllib.error.HTTPError) else ""
        log.warning("gemini_failed", extra={"error": e.__class__.__name__, "detail": detail})
        raise AssessmentError(f"AI assessment failed (Bedrock: {bedrock_error}, Gemini: {e.__class__.__name__})") from e
