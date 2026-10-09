#!/usr/bin/env bash
# LEAST-PRIVILEGE PROOF: the pipeline tries things it has no business doing,
# and this test PASSES only when AWS refuses every one of them.
#
# Every probe is a harmless "look, don't touch" request. If a permission were
# ever granted by mistake, the probe would only read a list, and this test
# would fail loudly.
set -uo pipefail
export AWS_PAGER=""

: "${S3_BUCKET:?S3_BUCKET is not set}"
failures=0

probe() {
  local what="$1"; shift
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "FAIL  ALLOWED, but should be refused: $what"
    failures=$((failures + 1))
  elif grep -qiE 'AccessDenied|UnauthorizedOperation|not authorized' <<<"$out"; then
    echo "PASS  Refused: $what"
  else
    echo "FAIL  Could not tell whether AWS refused: $what"
    echo "      $(head -n 1 <<<"$out")"
    failures=$((failures + 1))
  fi
}

probe "list every storage bucket in the account" aws s3api list-buckets
probe "read the security settings of its own bucket" aws s3api get-bucket-policy --bucket "$S3_BUCKET"
probe "list the people and robots with access to the account" aws iam list-users --max-items 1
probe "list the account's servers" aws ec2 describe-instances --max-items 1
probe "list the account's stored secrets" aws secretsmanager list-secrets --max-items 1

echo
if [[ $failures -gt 0 ]]; then
  echo "$failures probe(s) were not clearly refused. Treat the permissions as too broad until this passes."
  exit 1
fi
echo "All probes refused. The pipeline can publish the site and nothing else."
