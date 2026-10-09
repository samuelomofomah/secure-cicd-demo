#!/usr/bin/env bash
# AUDIT LOG: show every time someone signed in to AWS as the pipeline.
#
# AWS writes these records itself (the service is called CloudTrail). The
# pipeline cannot edit or delete them. New sign-ins can take up to 15 minutes
# to appear.
#
#   Usage:  bash audit.sh
set -euo pipefail
export AWS_PAGER=""

REGION="us-east-1"
ROLE_NAME="secure-cicd-demo-deploy"

command -v aws >/dev/null 2>&1 || { echo "The AWS CLI is not installed." >&2; exit 1; }

EVENTS="$(aws cloudtrail lookup-events --region "$REGION" \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 50 --output json)"

if command -v python3 >/dev/null 2>&1; then
  printf '%s' "$EVENTS" | ROLE_NAME="$ROLE_NAME" python3 -c '
import json, os, sys

role = os.environ["ROLE_NAME"]
rows = []
for item in json.load(sys.stdin).get("Events", []):
    event = json.loads(item.get("CloudTrailEvent") or "{}")
    request = event.get("requestParameters") or {}
    if not str(request.get("roleArn", "")).endswith("role/" + role):
        continue
    who = (event.get("userIdentity") or {}).get("userName", "unknown")
    result = "REFUSED (" + event["errorCode"] + ")" if event.get("errorCode") else "signed in"
    rows.append((event.get("eventTime", "?"), request.get("roleSessionName", "?"), result, who))

if not rows:
    print("No sign-ins recorded yet. Records can take up to 15 minutes to appear.")
    sys.exit(0)

head = ("When (UTC)", "Pipeline run", "Result", "Who GitHub said it was")
widths = [max(len(str(r[i])) for r in rows + [head]) for i in range(4)]
line = "  ".join("{:<" + str(w) + "}" for w in widths)
print(line.format(*head))
print(line.format(*["-" * w for w in widths]))
for r in rows:
    print(line.format(*r))
print()
print(str(len(rows)) + " sign-in record(s) for the role " + role + ".")
'
else
  # Without Python: a plainer table, straight from the AWS CLI.
  aws cloudtrail lookup-events --region "$REGION" \
    --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
    --max-results 50 \
    --query 'Events[].{When:EventTime,Who:Username,Action:EventName}' --output table
fi
