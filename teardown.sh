#!/usr/bin/env bash
# TEARDOWN: delete everything setup.sh created in AWS.
# CloudFront takes several minutes to switch off, so this is slow. Let it finish.
#
#   Usage:  bash teardown.sh
set -euo pipefail
cd "$(dirname "$0")"

if command -v terraform >/dev/null 2>&1; then TF=terraform
elif command -v tofu >/dev/null 2>&1; then TF=tofu
else echo "Terraform is not installed." >&2; exit 1
fi

[[ -f infra/terraform.tfvars ]] || { echo "Nothing to tear down: setup.sh has not been run from this folder." >&2; exit 1; }

"$TF" -chdir=infra destroy -input=false -auto-approve

echo
echo "AWS resources deleted. Two things are left for you to remove by hand if you want:"
echo "  1. The Slack app (api.slack.com/apps), which revokes the webhook."
echo "  2. The GitHub repository."
