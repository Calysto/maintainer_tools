#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/wait_for_label.sh"
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

check() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "OK: $desc"
  else
    echo "FAIL: $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=1
  fi
}

check_contains() {
  local desc="$1"
  local needle="$2"
  if grep -qF -- "$needle" "$TMPDIR/output.log"; then
    echo "OK: $desc"
  else
    echo "FAIL: $desc"
    echo "  expected to find: $needle"
    echo "  in: $(cat "$TMPDIR/output.log")"
    FAIL=1
  fi
}

# Fake `gh` that returns one canned list of labels per call. The Nth call prints
# the contents of $TMPDIR/resp<N> (empty when the file is missing), emulating
# `gh pr view ... --json labels --jq '.labels[].name'`.
FAKE_GH="$TMPDIR/gh"
cat > "$FAKE_GH" <<FAKE_GH_EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMPDIR/gh_calls.log"
COUNT_FILE="$TMPDIR/count"
count=\$(cat "\$COUNT_FILE" 2>/dev/null || echo 0)
count=\$((count + 1))
echo "\$count" > "\$COUNT_FILE"
cat "$TMPDIR/resp\${count}" 2>/dev/null || true
FAKE_GH_EOF
chmod +x "$FAKE_GH"
export PATH="$TMPDIR:$PATH"
export GH_TOKEN="test-token"
export GITHUB_REPOSITORY="owner/repo"

# resp <call-number> <label>...  - set the labels returned on a given call.
resp() {
  local n="$1"
  shift
  printf '%s\n' "$@" > "$TMPDIR/resp$n"
}

# reset - clear the fake gh call log, counter, and canned responses.
reset() {
  : > "$TMPDIR/gh_calls.log"
  echo 0 > "$TMPDIR/count"
  rm -f "$TMPDIR"/resp*
}

# run <required> <attempts> <delay>
run() {
  set +e
  bash "$SCRIPT" "42" "$1" "$2" "$3" > "$TMPDIR/output.log" 2>&1
  RC=$?
  set -e
}

# Case 1: required label present on the first check -> pass immediately.
reset
resp 1 "bug"
run "bug,enhancement" "2" "0"
check "present immediately: exit 0" 0 "$RC"
check "present immediately: one gh call" 1 "$(wc -l < "$TMPDIR/gh_calls.log")"

# Case 2: no label at first, appears on the retry -> pass.
reset
resp 1 "documentation"
resp 2 "maintenance"
run "bug,maintenance" "2" "0"
check "appears on retry: exit 0" 0 "$RC"
check "appears on retry: two gh calls" 2 "$(wc -l < "$TMPDIR/gh_calls.log")"

# Case 3: never labeled -> fail after exhausting attempts.
reset
resp 1 "documentation"
resp 2 "question"
run "bug,enhancement" "2" "0"
check "never labeled: exit 1" 1 "$RC"
check "never labeled: two gh calls" 2 "$(wc -l < "$TMPDIR/gh_calls.log")"
check_contains "never labeled: reports missing label" "missing a required label"

# Case 4: no labels at all -> fail.
reset
run "bug" "2" "0"
check "no labels: exit 1" 1 "$RC"

# Case 5: a single attempt checks once and does not sleep.
reset
resp 1 "documentation"
run "bug" "1" "0"
check "single attempt: exit 1" 1 "$RC"
check "single attempt: one gh call" 1 "$(wc -l < "$TMPDIR/gh_calls.log")"

# Case 6: label appears on a later attempt of a three-attempt run -> pass.
reset
resp 1 "documentation"
resp 2 "documentation"
resp 3 "enhancement"
run "bug,enhancement" "3" "0"
check "appears on third attempt: exit 0" 0 "$RC"
check "appears on third attempt: three gh calls" 3 "$(wc -l < "$TMPDIR/gh_calls.log")"

exit $FAIL
