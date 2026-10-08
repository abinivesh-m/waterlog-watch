# Demo video script (under 3:00)

Judges only see this video, so every second must show something working, and **AWS must be visible on screen**.
Record the phone with scrcpy (`scrcpy --record demo.mp4`) and the laptop with OBS. Speak in English and
add Tamil subtitles if you can.

| Time | Screen | Say |
|---|---|---|
| 0:00–0:15 | News clips or photos of Chennai/Mumbai waterlogging; a two-wheeler stuck in water | "Every monsoon, commuters drive into knee-deep water with zero warning. Two-wheelers stall, people fall into hidden open drains." |
| 0:15–0:25 | App opens and onboarding plays (Tamil selected) | "Waterlog Watch turns every phone into a flood sensor, in Tamil, Hindi and English." |
| 0:25–0:55 | Tap **Report flooding**, take a photo of a flooded street (or a puddle with a kerb), then **Analyse & report**. Result card: severity, depth, walk/bike/car, hazards, Tamil summary | "I snap a photo. **Amazon Bedrock** (Nova Lite) looks at it and estimates depth, severity, and who can pass safely. Non-flood photos are rejected, and **Amazon Rekognition** blocks unsafe images." |
| 0:55–1:20 | Map with coloured pins and glow. Tap a red pin to open the photo and details. Tap **Still flooded** | "The report is live for everyone nearby. Neighbours confirm or clear it, so the map heals itself. Old reports expire automatically with **DynamoDB TTL**." |
| 1:20–1:45 | Long-press a destination. Red **Avoid this route** card with the spots listed | "Before leaving, long-press your destination. Waterlog Watch checks your route against every live report." |
| 1:45–2:05 | Laptop: `/dashboard`, the ward command dashboard with KPIs and a ranked list. Click a row to zoom | "City officers get a live command dashboard, ranked by severity, to send pumps where they matter most." |
| 2:05–2:35 | AWS console: CloudFormation stack resources → Lambda → DynamoDB items → S3 photos → X-Ray trace map | "Everything is serverless on AWS, deployed from one SAM template: API Gateway, Lambda, Bedrock, Rekognition, DynamoDB, S3, with CloudWatch alarms and X-Ray tracing. It costs almost nothing when it's dry and scales when it pours." |
| 2:35–2:55 | Safety screen: one-tap 112 and GCC 1913, safety tips | "Plus one-tap emergency calls and monsoon safety tips." |
| 2:55–3:00 | Logo + GitHub URL | "Waterlog Watch. See the flood before you're in it." |

## Before recording
1. `python scripts/seed_demo.py` in CloudShell for a realistic Chennai map. Seeded spots are labelled "[Demo]"; say so on screen.
2. Do **one real report live** with a real photo, so judges see Bedrock actually working.
3. Afterwards, run `python scripts/seed_demo.py --clear`.
