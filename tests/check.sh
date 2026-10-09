#!/usr/bin/env bash
# QUALITY CHECKS: inspect the finished site before it is allowed to go live.
# Every check prints PASS or FAIL. One FAIL stops the release.
set -uo pipefail

DIR="${1:-dist}"
PAGE="$DIR/index.html"
failures=0

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }

# 1. The page exists at all.
if [[ -s "$PAGE" ]]; then
  pass "The page exists"
else
  fail "The page is missing or empty ($PAGE)"
  echo; echo "1 check failed. Release blocked."
  exit 1
fi

# 2. The browser tab has a title.
title="$(grep -o '<title>[^<]*</title>' "$PAGE" | sed -e 's/<[^>]*>//g' | xargs || true)"
if [[ -n "$title" ]]; then
  pass "The page has a title: \"$title\""
else
  fail "The page has no title"
fi

# 3. The headline is not blank.
headline="$(grep -o '<h1>[^<]*</h1>' "$PAGE" | sed -e 's/<[^>]*>//g' | xargs || true)"
if [[ -n "$headline" ]]; then
  pass "The headline is filled in: \"$headline\""
else
  fail "The headline is blank"
fi

# 4. No unfinished text made it through (TODO, FIXME, lorem ipsum).
#    HTML comments are stripped first, since visitors never see them.
visible="$(sed -e 's/<!--.*-->//g' "$PAGE")"
if grep -qiE 'TODO|FIXME|lorem ipsum' <<<"$visible"; then
  fail "Unfinished placeholder text is visible on the page"
else
  pass "No unfinished placeholder text"
fi

# 5. The release stamp was filled in by the build.
if grep -qE '\{\{|\}\}|\{%' "$PAGE"; then
  fail "The release stamp was not filled in"
else
  pass "The release stamp is filled in"
fi

# 6. Every local file the page points to is really there.
missing=0
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  case "$ref" in http://*|https://*|//*|'#'*|mailto:*|data:*) continue ;; esac
  if [[ ! -e "$DIR/$ref" ]]; then
    fail "The page points to a missing file: $ref"
    missing=1
  fi
done < <(grep -oE '(href|src)="[^"]*"' "$PAGE" | sed -E 's/^(href|src)="//; s/"$//')
[[ $missing -eq 0 ]] && pass "No broken links to local files"

echo
if [[ $failures -gt 0 ]]; then
  echo "$failures check(s) failed. Release blocked."
  exit 1
fi
echo "All checks passed. Safe to release."
