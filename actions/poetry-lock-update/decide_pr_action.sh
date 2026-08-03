#!/usr/bin/env bash
# Decide whether to open a new lock-update PR or refresh the existing open
# one on the same branch. An open PR already on $BRANCH is updated in
# place; a merged or manually-closed PR is not "open", so this naturally
# falls through to creating a fresh one — no extra state to track.
set -euo pipefail

BRANCH="$1"
TITLE="$2"
BODY="$3"
LABELS="$4"
DRY_RUN="$5"

PR_NUMBER=$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number // empty')

if [ -n "$PR_NUMBER" ]; then
  if [ "$DRY_RUN" = "true" ]; then
    echo "Would update PR #$PR_NUMBER (no new PR created)"
  else
    gh pr edit "$PR_NUMBER" --body "$BODY"
    echo "Updated PR #$PR_NUMBER"
  fi
else
  DRY_RUN_FLAG=""
  if [ "$DRY_RUN" = "true" ]; then
    DRY_RUN_FLAG="--dry-run"
  fi
  # shellcheck disable=SC2086
  gh pr create \
    --title "$TITLE" \
    --body "$BODY" \
    --label "$LABELS" \
    --head "$BRANCH" \
    $DRY_RUN_FLAG
fi
