"""Seed (or clear) clearly-labelled DEMO reports at well-known Chennai flood spots.

Use for the demo video when it isn't raining. Every seeded item has demo=True and its
note starts with "[Demo]", so it's never confused with a real citizen report.

IDs are derived from the spot name, so re-running overwrites the same 12 items
instead of creating duplicates. No --clear is needed between runs.

    python scripts/seed_demo.py                 # seed (live for 36 h)
    python scripts/seed_demo.py --hours 44      # live for 44 h (max)
    python scripts/seed_demo.py --clear         # remove all demo items
    python scripts/seed_demo.py --table NAME    # skip the CloudFormation lookup
"""
import argparse
import hashlib
import random
import sys
import time
from decimal import Decimal
from pathlib import Path

import boto3

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from app.geo import geohash  # noqa: E402

SPOTS = [
    # (name, lat, lng, depth, cm, severity, hazards)
    ("Madley Road subway, T. Nagar", 13.0378, 80.2296, "waist", 85, 5, ["subway flooded", "vehicles stranded"]),
    ("Velachery Main Road, Vijayanagar", 12.9750, 80.2210, "knee", 50, 4, ["open drain risk"]),
    ("Pallikaranai Marsh Road", 12.9380, 80.2130, "knee", 45, 4, ["fast current"]),
    ("Usman Road, T. Nagar", 13.0410, 80.2330, "ankle", 15, 2, []),
    ("Ashok Nagar 4th Avenue", 13.0370, 80.2120, "knee", 40, 3, ["potholes hidden"]),
    ("K.K. Nagar, Rajamannar Salai", 13.0390, 80.1990, "ankle", 20, 2, []),
    ("Saidapet bridge approach", 13.0230, 80.2230, "knee", 35, 3, ["slow traffic"]),
    ("OMR service road, Perungudi", 12.9650, 80.2460, "knee", 55, 4, ["open drain risk"]),
    ("Arcot Road, Vadapalani", 13.0500, 80.2120, "ankle", 18, 2, []),
    ("Mudichur, near lake bund", 12.9150, 80.0700, "waist", 90, 5, ["fast current", "electric pole in water"]),
    ("Pulianthope High Road", 13.0960, 80.2690, "knee", 40, 3, []),
    ("Kodambakkam High Road", 13.0520, 80.2250, "ankle", 12, 1, []),
]


def passable(sev):
    return {"pedestrian": sev <= 3, "two_wheeler": sev <= 2, "car": sev <= 3}


def summary(depth, cm, sev):
    words = {"ankle": "Ankle-deep", "knee": "Knee-deep", "waist": "Waist-deep"}[depth]
    advice = ("Avoid completely." if sev >= 5 else "Two-wheelers should avoid." if sev >= 3 else "Drive slowly.")
    ta = {"ankle": "கணுக்கால் அளவு", "knee": "முழங்கால் அளவு", "waist": "இடுப்பு அளவு"}[depth]
    ta_adv = ("முற்றிலும் தவிர்க்கவும்." if sev >= 5 else "இருசக்கர வாகனங்கள் தவிர்க்கவும்."
              if sev >= 3 else "மெதுவாக செல்லவும்.")
    return f"{words} water (~{cm} cm) on the road. {advice}", f"சாலையில் {ta} தண்ணீர் (~{cm} செ.மீ). {ta_adv}"


def table_name(stack, region):
    cfn = boto3.client("cloudformation", region_name=region)
    outs = cfn.describe_stacks(StackName=stack)["Stacks"][0]["Outputs"]
    return next(o["OutputValue"] for o in outs if o["OutputKey"] == "ReportsTableName")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stack", default="waterlog-watch")
    ap.add_argument("--region", default="ap-south-1")
    ap.add_argument("--clear", action="store_true")
    ap.add_argument("--table", help="DynamoDB table name (skips the CloudFormation lookup)")
    ap.add_argument("--hours", type=int, default=36, help="how long the spots stay live (max 44)")
    args = ap.parse_args()

    args.hours = min(args.hours, 44)  # the API only reads reports created in the last 48 h
    name_ = args.table or table_name(args.stack, args.region)
    table = boto3.resource("dynamodb", region_name=args.region).Table(name_)

    if args.clear:
        n = 0
        scan = {"FilterExpression": "demo = :t", "ExpressionAttributeValues": {":t": True}}
        while True:
            page = table.scan(**scan)
            for item in page.get("Items", []):
                table.delete_item(Key={"id": item["id"]})
                n += 1
            if "LastEvaluatedKey" not in page:
                break
            scan["ExclusiveStartKey"] = page["LastEvaluatedKey"]
        print(f"Removed {n} demo reports.")
        return

    now = int(time.time())
    for name, lat, lng, depth, cm, sev, hazards in SPOTS:
        created = now - random.randint(5, 150) * 60
        en, ta = summary(depth, cm, sev)
        table.put_item(Item={
            "id": hashlib.md5(name.encode()).hexdigest()[:12], "demo": True,
            "lat": Decimal(str(lat)), "lng": Decimal(str(lng)), "gh5": geohash(lat, lng, 5),
            "created_at": created, "updated_at": created, "expires_at": now + args.hours * 3600,
            "status": "active", "note": f"[Demo] {name}", "photo_key": "", "reporter": "demo-seed",
            "voters": {"demo-seed"}, "still_there": random.randint(1, 9), "cleared": 0,
            "is_waterlogging": True, "depth": depth, "depth_cm_estimate": cm, "severity": sev,
            "passable": passable(sev), "hazards": hazards, "summary": en, "summary_local": ta,
        })
    print(f"Seeded {len(SPOTS)} demo reports around Chennai (live for {args.hours} h). "
          f"Re-run to refresh; remove with --clear.")


if __name__ == "__main__":
    main()