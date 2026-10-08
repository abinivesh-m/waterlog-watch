import os

AWS_REGION = os.environ.get("AWS_REGION", "ap-south-1")
REPORTS_TABLE = os.environ.get("REPORTS_TABLE", "waterlog-reports")
PHOTOS_BUCKET = os.environ.get("PHOTOS_BUCKET", "waterlog-photos")
# Amazon Nova Lite: multimodal, cheap, served from Mumbai via the APAC inference profile.
BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "apac.amazon.nova-lite-v1:0")
BEDROCK_REGION = os.environ.get("BEDROCK_REGION", AWS_REGION)

REPORT_TTL_HOURS = int(os.environ.get("REPORT_TTL_HOURS", "12"))
CLEARED_VOTES_TO_CLOSE = int(os.environ.get("CLEARED_VOTES_TO_CLOSE", "3"))
MAX_IMAGE_BYTES = 4 * 1024 * 1024  # API Gateway/Lambda payload limits leave headroom at 4 MB
GEOHASH_PRECISION = 5
