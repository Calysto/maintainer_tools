#!/usr/bin/env bash
# Approve a bot-authored pull request and enable squash auto-merge on it.
#
# The GitHub App that opens these pull requests cannot approve its own PR
# ("Can not approve your own pull request"), so the approval is submitted with
# the workflow token instead, which is a different actor. This requires the
# caller's workflow to grant the default token `pull-requests: write`.
#
# Usage: auto_merge.sh <branch>
#
# Reads the following environment variables:
#   AUTO_MERGE      - "true" to act; any other value is a no-op
#   DRY_RUN         - "true" to skip all mutations
#   APP_TOKEN       - app installation token; when empty, approval is skipped
#                     (the workflow token would be the PR author)
#   WORKFLOW_TOKEN  - workflow token used to submit the approval
set -euo pipefail

BRANCH="$1"

if [ "${AUTO_MERGE:-false}" != "true" ] || [ "${DRY_RUN:-false}" = "true" ]; then
  exit 0
fi

if [ -n "${APP_TOKEN:-}" ]; then
  GH_TOKEN="${WORKFLOW_TOKEN:-}" gh pr review "$BRANCH" --approve
else
  echo "No app token configured; skipping approval"
fi

# The branch (and its PR) may be reused across runs, so only enable auto-merge
# when it is not already enabled, since re-enabling it errors. A failed lookup
# must fail the step rather than silently skipping the merge.
AUTO_MERGE_REQUEST=$(gh pr view "$BRANCH" --json autoMergeRequest --jq '.autoMergeRequest') || exit $?
if [ "$AUTO_MERGE_REQUEST" = "null" ]; then
  gh pr merge "$BRANCH" --auto --squash --delete-branch
fi
