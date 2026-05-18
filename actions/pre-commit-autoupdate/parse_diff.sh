#!/usr/bin/env bash
# Parse a git diff of .pre-commit-config.yaml and emit a markdown list of updates.
# Usage: parse_diff.sh <diff-file>
# Outputs lines of the form: "- <repo>: `<old>` → `<new>`"
set -euo pipefail

DIFF_FILE="${1:--}"

CURRENT_REPO=""
OLD_REV=""
while IFS= read -r line; do
  if [[ "$line" == " "* ]] && [[ "$line" =~ repo:[[:space:]]+(.*) ]]; then
    CURRENT_REPO=$(basename "${BASH_REMATCH[1]}")
  elif [[ "$line" =~ ^-[[:space:]]+rev:[[:space:]]+(.*) ]]; then
    OLD_REV="${BASH_REMATCH[1]//\'/}"
    OLD_REV="${OLD_REV//\"/}"
  elif [[ "$line" =~ ^\+[[:space:]]+rev:[[:space:]]+(.*) ]]; then
    NEW_REV="${BASH_REMATCH[1]//\'/}"
    NEW_REV="${NEW_REV//\"/}"
    echo "- ${CURRENT_REPO}: \`${OLD_REV}\` → \`${NEW_REV}\`"
  fi
done < <(cat "$DIFF_FILE")
