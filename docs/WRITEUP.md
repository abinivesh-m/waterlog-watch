# Waterlog Watch: short write-up for submission

**Track:** Heat and Water

**Problem.** In Indian cities, street waterlogging during monsoons strands commuters, stalls two-wheelers and hides open
drains. Information is scattered across WhatsApp forwards that are unverified, outdated and impossible to search by location.

**Solution.** Waterlog Watch is an Android app and a ward dashboard. Citizens photograph a flooded street, and
**Amazon Bedrock (Nova Lite, multimodal)** turns that photo into structured, verified data: depth, a severity from 1 to 5,
whether pedestrians, two-wheelers and cars can pass, hazards, and a summary in Tamil, Hindi or English. Reports appear on a live map,
merge when they're within 75 m of each other, are confirmed or cleared by neighbours, and expire on their own. Commuters long-press a destination to
check their route, and ward officers see a ranked command dashboard to deploy pumps.

**Built on AWS (one SAM template):**
- **Amazon Bedrock:** photo understanding through the Converse API, returning structured JSON
- **Amazon Rekognition:** content moderation before anything is posted publicly
- **AWS Lambda + Amazon API Gateway (HTTP API):** FastAPI backend with throttling
- **Amazon DynamoDB:** reports with a geohash GSI for nearby and route queries, and TTL auto-expiry
- **Amazon S3:** private, encrypted photo storage with presigned URLs and 7-day lifecycle deletion
- **Amazon CloudWatch + AWS X-Ray:** JSON logs, an error alarm, and per-request tracing

**Impact.** Fewer people walk or ride into dangerous water, ward officers get crowd-verified hotspots in real time,
and the data shows which streets flood every year, evidence for drainage fixes.

**What's next.** Area subscriptions with SMS alerts (Amazon SNS), IMD rainfall forecasts to predict flooding, and a
data feed for Greater Chennai Corporation's command centre.
