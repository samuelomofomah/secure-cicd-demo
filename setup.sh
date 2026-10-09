#!/usr/bin/env bash
# SETUP: build everything the pipeline needs in AWS, then print the three
# values GitHub needs to know (one secret, two variables).
#
#   Usage:  bash setup.sh your-github-username/secure-cicd-demo
#
# Safe to run again: it only changes what is different.
set -euo pipefail
cd "$(dirname "$0")"

REPO="${1:-}"
say() { printf '\n==> %s\n' "$1"; }
die() { printf '\nERROR: %s\n' "$1" >&2; exit 1; }

case "$REPO" in
  */*) ;;
  *) die "Tell me which repository to trust.  Usage: bash setup.sh your-github-username/secure-cicd-demo" ;;
esac

# ---- 1. Tools ----------------------------------------------------------------
command -v aws >/dev/null 2>&1 || die "The AWS CLI is not installed. See https://aws.amazon.com/cli/"
command -v curl >/dev/null 2>&1 || die "curl is not installed."
if command -v terraform >/dev/null 2>&1; then TF=terraform
elif command -v tofu >/dev/null 2>&1; then TF=tofu
else die "Terraform is not installed. On a Mac: brew install hashicorp/tap/terraform"
fi

# ---- 2. Which AWS account? ---------------------------------------------------
say "Checking your AWS sign-in"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" \
  || die "The AWS CLI is not signed in. Run 'aws configure' (or 'aws sso login') and try again."
echo "Signed in to the AWS account ending in ${ACCOUNT: -4}."

# ---- 3. Look up the repository's permanent IDs on GitHub ----------------------
say "Looking up github.com/$REPO"
JSON="$(curl -fsS -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$REPO" 2>/dev/null)" \
  || die "No public repository found at github.com/$REPO. Create it first and make sure it is Public."

FULL_NAME=""; REPO_ID=""; OWNER_ID=""
if command -v python3 >/dev/null 2>&1; then
  PARSED="$(printf '%s' "$JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["full_name"], d["id"], d["owner"]["id"])' 2>/dev/null || true)"
  FULL_NAME="$(printf '%s' "$PARSED" | cut -d' ' -f1)"
  REPO_ID="$(printf '%s' "$PARSED" | cut -d' ' -f2)"
  OWNER_ID="$(printf '%s' "$PARSED" | cut -d' ' -f3)"
fi
if [[ -z "$FULL_NAME" || -z "$REPO_ID" || -z "$OWNER_ID" ]]; then
  # Fallback without Python: the repository's id is indented two spaces, the owner's four.
  FULL_NAME="$(printf '%s\n' "$JSON" | grep -m1 '"full_name":' | sed -E 's/.*"full_name": *"([^"]+)".*/\1/')"
  REPO_ID="$(printf '%s\n' "$JSON" | grep -m1 -E '^  "id": *[0-9]+' | tr -dc '0-9')"
  OWNER_ID="$(printf '%s\n' "$JSON" | grep -m1 -E '^    "id": *[0-9]+' | tr -dc '0-9')"
fi
[[ -n "$FULL_NAME" && -n "$REPO_ID" && -n "$OWNER_ID" ]] || die "Could not read the repository details from GitHub."

OWNER="${FULL_NAME%%/*}"
NAME="${FULL_NAME#*/}"
echo "Found $FULL_NAME (owner ID $OWNER_ID, repository ID $REPO_ID)."

# ---- 4. Has this AWS account already registered GitHub as an identity provider?
# An account can do that only once, so reuse it if it is there.
CREATE_OIDC=true
if [[ -f infra/terraform.tfvars ]]; then
  # A previous run already decided. Keep that answer, or Terraform would undo it.
  grep -q '^create_oidc_provider *= *false' infra/terraform.tfvars && CREATE_OIDC=false
else
  EXISTING="$(aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text 2>/dev/null || true)"
  case "$EXISTING" in
    *token.actions.githubusercontent.com*) CREATE_OIDC=false ;;
  esac
fi
if [[ "$CREATE_OIDC" == "false" ]]; then
  echo "This AWS account already trusts GitHub as an identity provider. Reusing it."
fi

cat > infra/terraform.tfvars <<EOF
github_owner         = "$OWNER"
github_repo          = "$NAME"
github_owner_id      = "$OWNER_ID"
github_repo_id       = "$REPO_ID"
create_oidc_provider = $CREATE_OIDC
EOF

# ---- 5. Build it -------------------------------------------------------------
say "Preparing Terraform"
"$TF" -chdir=infra init -input=false >/dev/null || die "Terraform could not initialise. Run '$TF -chdir=infra init' to see why."

say "Creating the AWS resources (the CloudFront part takes about 4 minutes)"
"$TF" -chdir=infra apply -input=false -auto-approve

ROLE_ARN="$("$TF" -chdir=infra output -raw AWS_ROLE_ARN)"
BUCKET="$("$TF" -chdir=infra output -raw S3_BUCKET)"
SITE_URL="$("$TF" -chdir=infra output -raw SITE_URL)"

# ---- 6. Hand the three values to GitHub --------------------------------------
# The role's address is not a password, but it contains the AWS account number,
# and a public repository's logs can be read by anyone. Saving it as a secret
# keeps it out of them.
SET_BY_GH=false
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if gh secret set AWS_ROLE_ARN --repo "$FULL_NAME" --body "$ROLE_ARN" >/dev/null 2>&1 \
    && gh variable set S3_BUCKET --repo "$FULL_NAME" --body "$BUCKET" >/dev/null 2>&1 \
    && gh variable set SITE_URL --repo "$FULL_NAME" --body "$SITE_URL" >/dev/null 2>&1; then
    SET_BY_GH=true
  fi
fi

echo
echo "=================================================================="
echo " AWS is ready."
echo
if [[ "$SET_BY_GH" == "true" ]]; then
  echo " These were saved to $FULL_NAME for you. Nothing to paste."
else
  echo " Add these in GitHub: Settings > Secrets and variables > Actions"
fi
echo
echo " SECRETS tab"
echo "   AWS_ROLE_ARN   $ROLE_ARN"
echo
echo " VARIABLES tab"
echo "   S3_BUCKET      $BUCKET"
echo "   SITE_URL       $SITE_URL"
echo
echo " You still need to add the SLACK_WEBHOOK_URL secret yourself."
echo "=================================================================="
