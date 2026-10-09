#!/usr/bin/env bash
# SECRET SCAN: refuse any change that has a password or key written into the code.
#
# Secrets belong in a vault (GitHub Actions secrets, AWS), never in a file that
# is saved to the repository, because the repository remembers everything forever.
# This is a small demo scanner that shows the idea. On a real project, use a
# dedicated tool such as gitleaks alongside GitHub's own secret scanning.
#
# It prints the file and line number of each finding, never the secret itself,
# because pipeline logs are readable by other people.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# name|pattern  (extended regular expressions, matched case-insensitively)
RULES=(
  'AWS access key ID|AKIA[0-9A-Z]{16}'
  'AWS secret access key|aws_secret_access_key[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9/+=]{30,}'
  'Slack webhook URL|hooks\.slack\.com/services/T[A-Za-z0-9]+/B[A-Za-z0-9]+/[A-Za-z0-9]{10,}'
  'Slack token|xox[baprs]-[A-Za-z0-9-]{10,}'
  'GitHub token|gh[pousr]_[A-Za-z0-9]{30,}'
  'Private key|-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'Hard-coded password or token|(password|passwd|secret|token|api[_-]?key)[a-z0-9_]*[[:space:]]*[=:][[:space:]]*["'"'"'][^"'"'"'$ {<][^"'"'"' ]{7,}["'"'"']'
)

# Files to scan: everything saved in the repository, except this scanner
# (which contains the patterns) and the README (which shows an example secret
# for the walkthrough).
list_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files --cached --others --exclude-standard
  else
    find . -type f -not -path './.git/*' -not -path './dist/*' \
      -not -path './infra/.terraform/*' | sed 's|^\./||'
  fi
}
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(list_files)

findings=0
for file in "${FILES[@]}"; do
  case "$file" in tests/secret_scan.sh|README.md) continue ;; esac
  [[ -f "$file" ]] || continue
  grep -Iq . "$file" 2>/dev/null || continue   # skip binary and empty files
  for rule in "${RULES[@]}"; do
    name="${rule%%|*}"
    pattern="${rule#*|}"
    while IFS=: read -r line _; do
      [[ -z "$line" ]] && continue
      echo "FAIL  $name found in $file, line $line"
      findings=$((findings + 1))
    done < <(grep -nIiE -e "$pattern" "$file" 2>/dev/null)
  done
done

echo
if [[ $findings -gt 0 ]]; then
  echo "$findings possible secret(s) found in the code. Release blocked."
  echo "Remove it, store it as a secret instead, and treat the exposed value as compromised."
  exit 1
fi
echo "PASS  No passwords or keys are written into the code (${#FILES[@]} files scanned)."
