# Waterlog Watch: write-up

**Track:** Heat and Water · **Team:** Abinivesh M
**Live API:** https://lwj4clgh53.execute-api.ap-south-1.amazonaws.com · **Ward dashboard:** https://lwj4clgh53.execute-api.ap-south-1.amazonaws.com/dashboard

## Problem
Every monsoon, street waterlogging in Indian cities strands commuters, stalls two-wheelers and hides open drains.
Warnings come as unverified WhatsApp forwards that are outdated and can't be searched by location.

## Solution
Waterlog Watch is an Android app plus a ward dashboard.
- **Report:** a citizen photographs a flooded street. The AI checks the photo and returns the depth (ankle, knee or waist),
  a severity from 1 to 5, who can pass (walking, two-wheeler or car), hazards (open drains, live wires) and a
  summary in **Tamil, Hindi or English**. Photos that aren't of flooding are rejected automatically.
- **Live map:** reports within 75 m merge into one spot. Neighbours tap *Still flooded* or *Cleared*, and stale spots
  expire on their own.
- **Route check:** long-press a destination to get a real road route (Amazon Location Service), checked against every
  flooded spot on it. The verdict depends on how you travel: knee-deep water means "Avoid" on a scooter but "Caution" in a car.
- **Ward command dashboard:** live hotspots ranked by severity, so officers know where to send pumps first.
- **Safety:** one-tap calls to 112 and the Chennai Corporation flood helpline (1913), plus monsoon safety tips.

## Built on AWS (deployed in ap-south-1, Mumbai, from one CloudFormation/SAM template)
- **AWS Lambda + Amazon API Gateway (HTTP API):** Python FastAPI backend with rate limiting
- **Amazon DynamoDB:** reports with a geohash GSI for nearby and route queries, and TTL auto-expiry
- **Amazon S3:** private, encrypted photo storage with presigned URLs and 7-day lifecycle deletion
- **Amazon Location Service (Routes API):** real road routes for scooter, car and walking
- **Amazon Bedrock (Nova Lite, Converse API):** the primary photo-understanding model
- **Amazon Rekognition:** content moderation before anything is posted publicly
- **Amazon CloudWatch + AWS X-Ray:** JSON logs, an error alarm, and request tracing
- **AWS CloudFormation / SAM:** all infrastructure as code

**Transparency note:** our new AWS account is still finishing verification, and during that period Bedrock (and
CloudShell) are blocked at the account level ("Operation not allowed"). The backend therefore calls Bedrock first
and, only if Bedrock refuses, falls back to Google Gemini with the same prompt. Every report records which model
produced it (`ai_provider`). Once verification completes, Bedrock takes over automatically with no redeploy.

## Impact
Fewer people walk or ride into dangerous water, ward officers get crowd-verified hotspots in real time, and the
data builds a record of which streets flood every year, evidence for fixing drainage.

## What's next
SMS alerts for subscribed streets (Amazon SNS), IMD rainfall forecasts to predict flooding before it happens, and a
data feed for the Greater Chennai Corporation's command centre.

## AI tools used
Designed and built by Abinivesh M. Used Claude for coding assistance.
