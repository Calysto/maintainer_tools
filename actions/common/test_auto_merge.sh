#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/auto_merge.sh"
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

check_contains() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "OK: $desc"
  else
    echo "FAIL: $desc"
    echo "  expected to find: $needle"
    echo "  in: $haystack"
    FAIL=1
  fi
}

check_not_contains() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "FAIL: $desc"
    echo "  expected NOT to find: $needle"
    echo "  in: $haystack"
    FAIL=1
  else
    echo "OK: $desc"
  fi
}

# Fake `gh` that logs the effective GH_TOKEN and arguments for every call. For
# `pr view` it evaluates the caller's real --jq expression against a canned PR
# JSON document, or fails when the pr_view_fail sentinel exists. Like gh's
# built-in jq (and unlike jq -r), a null result prints as an empty line, so a
# script that tests for the string "null" fails here as it does in production.
# This is not a general gh emulator — it only handles the exact call shapes
# auto_merge.sh makes.
FAKE_GH="$TMPDIR/gh"
cat > "$FAKE_GH" <<FAKE_GH_EOF
#!/usr/bin/env bash
echo "GH_TOKEN=\${GH_TOKEN:-} :: \$*" >> "$TMPDIR/gh_calls.log"
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  if [ -f "$TMPDIR/pr_view_fail" ]; then
    exit 1
  fi
  EXPR="."
  while [ \$# -gt 0 ]; do
    if [ "\$1" = "--jq" ]; then
      EXPR="\$2"
      shift
    fi
    shift
  done
  jq -r "\$EXPR | if . == null then \"\" else . end" "$TMPDIR/pr_view_response"
fi
FAKE_GH_EOF
chmod +x "$FAKE_GH"
export PATH="$TMPDIR:$PATH"

# run <auto_merge> <dry_run> <app_token> <pr_view_json>
run() {
  echo "$4" > "$TMPDIR/pr_view_response"
  : > "$TMPDIR/gh_calls.log"
  rm -f "$TMPDIR/pr_view_fail"
  AUTO_MERGE="$1" DRY_RUN="$2" APP_TOKEN="$3" WORKFLOW_TOKEN="workflow-token" \
    bash "$SCRIPT" "poetry-lock-update" > "$TMPDIR/output.log" 2>&1
}

NOT_ENABLED='{"autoMergeRequest":null}'
ENABLED='{"autoMergeRequest":{"enabledBy":{"login":"x"}}}'

# Case 1: disabled -> no gh calls at all
run "false" "false" "app-token" "$NOT_ENABLED"
CALLS=$(cat "$TMPDIR/gh_calls.log")
if [ -z "$CALLS" ]; then
  echo "OK: disabled: no gh calls"
else
  echo "FAIL: disabled: expected no gh calls, got: $CALLS"
  FAIL=1
fi

# Case 2: dry-run -> no gh calls at all
run "true" "true" "app-token" "$NOT_ENABLED"
CALLS=$(cat "$TMPDIR/gh_calls.log")
if [ -z "$CALLS" ]; then
  echo "OK: dry-run: no gh calls"
else
  echo "FAIL: dry-run: expected no gh calls, got: $CALLS"
  FAIL=1
fi

# Case 3: opt-in, not yet enabled -> approve with the workflow token, then merge
run "true" "false" "app-token" "$NOT_ENABLED"
CALLS=$(cat "$TMPDIR/gh_calls.log")
check_contains "opt-in: approves with the workflow token" "GH_TOKEN=workflow-token :: pr review poetry-lock-update --approve" "$CALLS"
check_contains "opt-in: enables squash auto-merge" "pr merge poetry-lock-update --auto --squash --delete-branch" "$CALLS"

# Case 4: already enabled -> approve, but do not re-enable
run "true" "false" "app-token" "$ENABLED"
CALLS=$(cat "$TMPDIR/gh_calls.log")
check_contains "already enabled: still approves" "pr review poetry-lock-update --approve" "$CALLS"
check_not_contains "already enabled: does NOT re-enable auto-merge" "pr merge" "$CALLS"

# Case 5: no app token -> skip approval, still enable auto-merge
run "true" "false" "" "$NOT_ENABLED"
CALLS=$(cat "$TMPDIR/gh_calls.log")
check_not_contains "no app token: does NOT approve" "pr review" "$CALLS"
check_contains "no app token: still enables auto-merge" "pr merge poetry-lock-update --auto --squash --delete-branch" "$CALLS"

# Case 6: gh pr view fails -> step fails, no merge attempted
echo "$NOT_ENABLED" > "$TMPDIR/pr_view_response"
: > "$TMPDIR/gh_calls.log"
touch "$TMPDIR/pr_view_fail"
set +e
AUTO_MERGE="true" DRY_RUN="false" APP_TOKEN="app-token" WORKFLOW_TOKEN="workflow-token" \
  bash "$SCRIPT" "poetry-lock-update" > "$TMPDIR/output.log" 2>&1
RC=$?
set -e
CALLS=$(cat "$TMPDIR/gh_calls.log")
if [ "$RC" -ne 0 ]; then
  echo "OK: lookup failure: non-zero exit ($RC)"
else
  echo "FAIL: lookup failure: expected non-zero exit"
  FAIL=1
fi
check_not_contains "lookup failure: does NOT enable auto-merge" "pr merge" "$CALLS"

exit $FAIL
