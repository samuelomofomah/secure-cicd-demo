#!/usr/bin/env bash
# SLACK ALERT: tell the team what just happened, pass or fail.
#
# The webhook URL is a secret. It arrives as an environment variable from
# GitHub's encrypted secret store and is never written to a file or printed.
set -euo pipefail

if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
  echo "::warning::SLACK_WEBHOOK_URL secret is not set, so no Slack alert was sent."
  exit 0
fi

# A job that did not run reports "skipped". Only a real failure or a
# cancellation counts as a failed pipeline.
failed=()
[[ "${CHECK_RESULT:-}" == "failure" || "${CHECK_RESULT:-}" == "cancelled" ]] && failed+=("Test and scan")
[[ "${LOCKDOWN_RESULT:-}" == "failure" || "${LOCKDOWN_RESULT:-}" == "cancelled" ]] && failed+=("Pull request lockdown proof")
[[ "${DEPLOY_RESULT:-}" == "failure" || "${DEPLOY_RESULT:-}" == "cancelled" ]] && failed+=("Deploy to AWS")

# Slack treats & < > as formatting characters, so escape them in free text.
esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<<"$1"; }
title="$(esc "$(head -n 1 <<<"${CHANGE_TITLE:-a change}")")"
actor="$(esc "${ACTOR:-someone}")"

if [[ ${#failed[@]} -gt 0 ]]; then
  stage="$(printf '%s, ' "${failed[@]}")"
  stage="${stage%, }"
  text=":x: *Blocked.* \"${title}\" by ${actor} did not pass: ${stage}. Nothing was published. <${RUN_URL}|See why>"
elif [[ "${DEPLOY_RESULT:-}" == "success" ]]; then
  text=":white_check_mark: *Release #${RUN_NUMBER} is live.* \"${title}\" by ${actor}. <${SITE_URL:-$RUN_URL}|Open the site> · <${RUN_URL}|Pipeline run>"
else
  text=":white_check_mark: *Checks passed.* \"${title}\" by ${actor} is safe to merge. <${RUN_URL}|Details>"
fi

payload="$(jq -n --arg text "$text" '{text: $text}')"

curl --silent --show-error --fail --max-time 15 \
  -X POST -H 'Content-type: application/json' \
  --data "$payload" "$SLACK_WEBHOOK_URL" >/dev/null

echo "Slack alert sent."
