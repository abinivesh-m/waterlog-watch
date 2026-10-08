# Building Waterlog Watch: AI-verified flood alerts for Indian streets, serverless on AWS

*Bharat Builds Tour · Environmental Hacks · Heat and Water track · by Abinivesh M*

Every northeast monsoon, Chennai's streets turn into rivers. The Madley Road subway fills, Velachery and Pallikaranai
go under, and commuters find out the hard way, usually on a two-wheeler and knee-deep in water. The information
exists: people take photos and send them around on WhatsApp. But those forwards are unverified, quickly outdated, and
impossible to search by *"is my route safe right now?"*

**Waterlog Watch** turns those photos into a live, verified flood map. In this post I walk through how I built it
during the hackathon, entirely on AWS serverless, and what I learned along the way.

![Architecture](architecture.png)

## What it does

1. **Snap:** a citizen photographs a flooded street in the Android app.
2. **Verify:** an AI vision model returns structured data: the water depth (ankle, knee or waist), a severity from 1
   to 5, who can pass (walking, two-wheeler or car), hazards such as open drains or live wires, and a one-line summary
   in **Tamil, Hindi or English**. Photos that aren't of flooding are rejected, so the map can't be spammed.
3. **Warn:** the spot appears on a live map with a coloured, severity-scaled glow.
4. **Route check:** long-press your destination. The app gets a **real road route from Amazon Location Service** and
   checks it against every active report. The verdict depends on how you travel: knee-deep water means *Avoid* on a
   scooter but only *Caution* in a car.
5. **Self-healing:** neighbours tap *Still flooded* or *Cleared*. Three "cleared" votes close a spot, and stale reports
   expire automatically.
6. **Ward command dashboard:** officers get a live web dashboard ranking hotspots by severity, so pumps go where
   they matter most.

## The architecture

Everything runs in **ap-south-1 (Mumbai)** and is defined in a single **AWS SAM / CloudFormation** template.

| Service | Role |
|---|---|
| **Amazon API Gateway (HTTP API)** | HTTPS entry point, CORS and throttling (burst 50, rate 20 per second) |
| **AWS Lambda** (Python 3.12) | A FastAPI app wrapped with Mangum: reports, nearby queries, votes, route checks and the dashboard |
| **Amazon Bedrock** (Nova Lite, Converse API) | Multimodal photo assessment that returns strict JSON |
| **Amazon Rekognition** | `DetectModerationLabels` blocks unsafe images before anything is published |
| **Amazon Location Service** (Routes v2) | Real road routes for scooter, car and pedestrian |
| **Amazon DynamoDB** | Reports, a geohash GSI for spatial queries, and TTL for automatic expiry |
| **Amazon S3** | Private, encrypted photo storage, presigned URLs and a 7-day lifecycle rule |
| **Amazon CloudWatch + AWS X-Ray** | JSON logs, an error alarm, and per-request tracing |

### 1. Turning a photo into data with Bedrock

The key design decision was to make the model return **structured JSON** rather than prose, so the rest of the
system can work with numbers instead of text:

```python
resp = bedrock.converse(
    modelId="apac.amazon.nova-lite-v1:0",
    messages=[{"role": "user", "content": [
        {"image": {"format": "jpeg", "source": {"bytes": photo}}},
        {"text": PROMPT},   # asks for is_waterlogging, depth, severity, passable{}, hazards[], summary, summary_local
    ]}],
    inferenceConfig={"maxTokens": 600, "temperature": 0.1},
)
```

The prompt tells the model to use visual cues (kerbs, tyres, people's legs) and to *be conservative about safety*.
A `normalise()` step clamps severity to 1–5, validates the depth label, and fills sensible defaults, so a
slightly malformed reply can never break the app. If `is_waterlogging` is false, the API returns HTTP 422 with the
model's own explanation (for example *"The image shows a food dish and not a street scene"*).

### 2. "What's near me?" in DynamoDB without a geo database

DynamoDB has no built-in spatial index, so each report stores a **5-character geohash** (cells of roughly 4.9 km)
as the partition key of a GSI, with `created_at` as the sort key. A nearby query works out which cells overlap the
search circle, queries only those partitions, then filters by exact haversine distance. It's cheap and fast, and
it scales the way DynamoDB does.

Reports carry an `expires_at` attribute with **DynamoDB TTL** enabled. Every *Still flooded* confirmation pushes it
forward, so active floods stay on the map while abandoned reports disappear on their own.

Duplicates are handled at write time: a new report within 75 m of an active one becomes a confirmation of the
existing spot instead of a new pin. Votes use a DynamoDB **condition expression** (`NOT contains(voters, :device)`),
so each device can vote only once per spot, atomically and with no extra reads.

### 3. Mode-aware route checks with Amazon Location Service

A straight line between two points says nothing about flooding on the roads you'll actually take. So the Lambda calls
`geo-routes:CalculateRoutes` with `TravelMode` set to `Scooter`, `Car` or `Pedestrian`, gets the real road
polyline, and measures each active report's distance to that polyline. Reports within 60 m count as *on the
route*, and the result tells you how far along the road each one is.

The verdict depends on how you travel: a spot whose `passable.two_wheeler` is false turns a scooter route red even if a
car could get through. Two-wheelers matter here because in Indian cities they're the vehicles most at risk in floods.

### 4. The ward dashboard

The same Lambda serves a single HTML page at `/dashboard`: Leaflet with OpenStreetMap tiles, KPI cards (active
spots, dangerous spots, spots cars can't pass, citizen confirmations), and a list ranked by severity that refreshes every 30
seconds. Running it from the same Lambda meant no extra infrastructure.

## Deploying without CloudShell

My AWS account was brand new, and during verification **CloudShell and Bedrock were blocked** ("Operation not
allowed"). Two things got me through:

- **Deploying without a shell.** I built the Lambda package for Linux and Python 3.12 using
  `pip install --platform manylinux2014_x86_64 --python-version 3.12 --only-binary=:all:`, uploaded the zip and the
  template to S3, and created the stack from the CloudFormation console. The SAM transform still works there.
- **A provider fallback for the vision model.** The backend calls Bedrock first. If Bedrock refuses, it sends the same
  prompt to Gemini and records `ai_provider` on every report. When the account finishes verification, Bedrock takes
  over automatically with no redeploy. Being open about that matters: every report shows which model produced it.

## Testing

The backend has a pytest suite that uses **moto** to mock DynamoDB, S3 and CloudFormation. It covers report merging,
one-vote-per-device, mode-aware route verdicts against a fake Amazon Location response, the moderation block and the AI
fallback. I also tested the deployed API with real Chennai monsoon photos from Wikimedia Commons. One photo I had
labelled "dry road" was correctly rated severity 2 (it showed post-flood mud and potholes), and a food photo was
rejected.

## Cost

It's all pay-per-request: Lambda, the HTTP API, on-demand DynamoDB, and S3 with a lifecycle rule. When it's not raining the cost
is effectively zero. When it pours, everything scales automatically.

## What's next

- Subscribe to a street and get an SMS alert when it floods (Amazon SNS)
- Combine reports with IMD rainfall forecasts to predict which streets will flood *before* the rain
- An open data feed for the Greater Chennai Corporation's command centre

## Try it

- **Code:** https://github.com/abinivesh-m/waterlog-watch
- **Live ward dashboard:** https://lwj4clgh53.execute-api.ap-south-1.amazonaws.com/dashboard
- **API docs:** https://lwj4clgh53.execute-api.ap-south-1.amazonaws.com/docs

*AI tools used: Claude helped generate code, set up the deployment and draft this post.*
