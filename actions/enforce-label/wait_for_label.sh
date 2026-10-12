#!/usr/bin/env bash
# Enforce that a pull request carries at least one required label, waiting
# briefly for a label to be applied.
#
# Unlike yogevbd/enforce-label-action (which reads the labels frozen into the
# event payload), this polls the live pull request through the API. That gives
# the author a grace period to label a freshly opened PR before the check fails.
#
# Usage: wait_for_label.sh <pr-number> <required-labels> [attempts] [delay-seconds]
#
# Reads the following environment variables:
#   GH_TOKEN          - token used by `gh` to read the pull request
#   GITHUB_REPOSITORY - "owner/repo" of the pull request
set -euo pipefail

PR="${1:?pull request number is required}"
REQUIRED="${2:?at least one required label is required}"
ATTEMPTS="${3:-2}"
DELAY="${4:-60}"

IFS=',' read -r -a required_labels <<< "$REQUIRED"

label_present() {
  local labels label required
  labels=$(gh pr view "$PR" --repo "$GITHUB_REPOSITORY" --json labels --jq '.labels[].name')
  while IFS= read -r label; do
    [ -z "$label" ] && continue
    for required in "${required_labels[@]}"; do
      if [ "$label" = "$required" ]; then
        return 0
      fi
    done
  done <<< "$labels"
  return 1
}

for (( attempt = 1; attempt <= ATTEMPTS; attempt++ )); do
  if label_present; then
    echo "Pull request #${PR} has a required label."
    exit 0
  fi
  if (( attempt < ATTEMPTS )); then
    echo "No required label on pull request #${PR}; retrying in ${DELAY}s (attempt ${attempt}/${ATTEMPTS})."
    sleep "$DELAY"
  fi
done

echo "::error::Pull request #${PR} is missing a required label. Select at least one: ${REQUIRED}"
exit 1
