#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/decide_pr_action.sh"
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

# Fake `gh` that logs every invocation to gh_calls.log and, for `pr list`,
# answers from a canned JSON response file the test sets up beforehand.
# This is not a general gh emulator — it only handles the exact call
# shapes decide_pr_action.sh makes.
FAKE_GH="$TMPDIR/gh"
cat > "$FAKE_GH" <<FAKE_GH_EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMPDIR/gh_calls.log"
if [ "\$1" = "pr" ] && [ "\$2" = "list" ]; then
  jq -r '.[0].number // empty' "$TMPDIR/pr_list_response.json"
fi
FAKE_GH_EOF
chmod +x "$FAKE_GH"
export PATH="$TMPDIR:$PATH"

run_script() {
  local pr_list_json="$1"
  shift
  echo "$pr_list_json" > "$TMPDIR/pr_list_response.json"
  : > "$TMPDIR/gh_calls.log"
  bash "$SCRIPT" "$@" > "$TMPDIR/output.log" 2>&1 || true
}

# Case 1: no open PR -> should create
run_script '[]' "poetry-lock-update" "chore: update poetry.lock" "BODY1" "maintenance" "false"
CALLS=$(cat "$TMPDIR/gh_calls.log")
check_contains "no open PR: gh pr create is called" "pr create" "$CALLS"
check_contains "no open PR: create uses --head poetry-lock-update" "--head poetry-lock-update" "$CALLS"
check_not_contains "no open PR: gh pr edit is NOT called" "pr edit" "$CALLS"
check_contains "pr list uses --state open" "--state open" "$CALLS"

# Case 2: open PR #42 -> should edit, not create
run_script '[{"number": 42}]' "poetry-lock-update" "chore: update poetry.lock" "BODY2" "maintenance" "false"
CALLS=$(cat "$TMPDIR/gh_calls.log")
check_contains "open PR: gh pr edit 42 is called" "pr edit 42" "$CALLS"
check_not_contains "open PR: gh pr create is NOT called" "pr create" "$CALLS"
check_contains "open PR: edit re-applies label" "--add-label maintenance" "$CALLS"

# Case 3: open PR #42, dry-run -> should neither edit nor create, and say so
run_script '[{"number": 42}]' "poetry-lock-update" "chore: update poetry.lock" "BODY3" "maintenance" "true"
CALLS=$(cat "$TMPDIR/gh_calls.log")
OUTPUT=$(cat "$TMPDIR/output.log")
check_not_contains "open PR + dry-run: gh pr edit is NOT called" "pr edit" "$CALLS"
check_not_contains "open PR + dry-run: gh pr create is NOT called" "pr create" "$CALLS"
check_contains "open PR + dry-run: output mentions PR #42" "PR #42" "$OUTPUT"

# Case 4: no open PR, dry-run -> should create with --dry-run
run_script '[]' "poetry-lock-update" "chore: update poetry.lock" "BODY4" "maintenance" "true"
CALLS=$(cat "$TMPDIR/gh_calls.log")
check_contains "no open PR + dry-run: gh pr create is called" "pr create" "$CALLS"
check_contains "no open PR + dry-run: create passes --dry-run" "--dry-run" "$CALLS"

exit $FAIL
