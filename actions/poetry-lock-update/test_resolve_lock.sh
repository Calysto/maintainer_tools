#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/resolve_lock.py"
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

# Print culprits as "name==version" pairs, comma separated, sorted.
culprits() {
  local fixture="$1"
  local excluded="${2-}"
  DIR="$DIR" FIXTURE="$fixture" EXCLUDED="$excluded" python3 - <<'PY'
import os
import sys

sys.path.insert(0, os.environ["DIR"])
import resolve_lock

output = open(os.environ["FIXTURE"]).read()
excluded = {e for e in os.environ["EXCLUDED"].split(",") if e}
found = resolve_lock.find_culprits(output, excluded)
print(",".join(f"{n}=={v}" for n, v in sorted(found.items())))
PY
}

cat > "$TMPDIR/cooldown.txt" <<'EOF'
Updating dependencies
Resolving dependencies...
Source (PyPI): The following package versions were ignored due to solver.min-release-age=7
Source (PyPI): metakernel: 1.0.6, 1.0.7
Source (PyPI): mypy: 2.3.1

Because octave-kernel depends on metakernel (>=1.0.6) which doesn't match any versions, version solving failed.
EOF

check "waives only the blamed package" \
  "metakernel==1.0.7" \
  "$(culprits "$TMPDIR/cooldown.txt")"

check "skips packages already excluded" \
  "" \
  "$(culprits "$TMPDIR/cooldown.txt" "metakernel")"

cat > "$TMPDIR/genuine.txt" <<'EOF'
Updating dependencies
Resolving dependencies...
Source (PyPI): The following package versions were ignored due to solver.min-release-age=7
Source (PyPI): mypy: 2.3.1

Because octave-kernel depends on both foo (>=2.0) and bar (<1.0), version solving failed.
EOF

check "genuine conflict yields no culprits" \
  "" \
  "$(culprits "$TMPDIR/genuine.txt")"

cat > "$TMPDIR/normalize.txt" <<'EOF'
Resolving dependencies...
Source (PyPI): The following package versions were ignored due to solver.min-release-age=7
Source (PyPI): Foo_Bar: 3.1.0

Because widget depends on foo-bar (>=3.1.0) which doesn't match any versions, version solving failed.
EOF

check "matches names across PEP 503 normalization" \
  "foo-bar==3.1.0" \
  "$(culprits "$TMPDIR/normalize.txt")"

cat > "$TMPDIR/clean.txt" <<'EOF'
Updating dependencies
Resolving dependencies...
Writing lock file
EOF

check "no cooldown block yields no culprits" \
  "" \
  "$(culprits "$TMPDIR/clean.txt")"

# Regression for parse_blamed over-waiving: a package literally named
# "dependencies" is suppressed by the cooldown, and Poetry's own fixed status
# lines ("Updating dependencies", "Resolving dependencies...") contain that
# same word. Only the solver's actual failure explanation (starting at the
# first "Because " line) may blame a package, so this must NOT be waived even
# though its name collides with the status-line text; only the genuinely
# blamed "mypy" should come out.
cat > "$TMPDIR/status_line_collision.txt" <<'EOF'
Updating dependencies
Resolving dependencies...
Source (PyPI): The following package versions were ignored due to solver.min-release-age=7
Source (PyPI): dependencies: 1.0.0
Source (PyPI): mypy: 2.3.1

Because octave-kernel depends on mypy (>=2.3.1) which doesn't match any versions, version solving failed.
EOF

check "status-line words are never treated as blamed packages" \
  "mypy==2.3.1" \
  "$(culprits "$TMPDIR/status_line_collision.txt")"

# --- Retry loop ---------------------------------------------------------
# Fake `poetry` on PATH: attempt N prints out.N, exits with code.N, and records
# the exclude list it was given to exclude.N.
STUB_DIR="$TMPDIR/stub"
mkdir -p "$STUB_DIR/bin"
cat > "$STUB_DIR/bin/poetry" <<'EOF'
#!/usr/bin/env bash
N=$(cat "$STUB_DIR/attempt")
N=$((N + 1))
echo "$N" > "$STUB_DIR/attempt"
printf '%s' "${POETRY_SOLVER_MIN_RELEASE_AGE_EXCLUDE-}" > "$STUB_DIR/exclude.$N"
printf '%s' "${POETRY_SOLVER_MIN_RELEASE_AGE-}" > "$STUB_DIR/age.$N"
[ -f "$STUB_DIR/out.$N" ] && cat "$STUB_DIR/out.$N"
[ -f "$STUB_DIR/code.$N" ] && exit "$(cat "$STUB_DIR/code.$N")"
exit 0
EOF
chmod +x "$STUB_DIR/bin/poetry"

# Reset stub state and run resolve_lock.py in a scratch working directory.
# Sets: RC, GH_OUTPUT, RUN_DIR.
run_resolve() {
  rm -f "$STUB_DIR"/out.* "$STUB_DIR"/code.* "$STUB_DIR"/exclude.* "$STUB_DIR"/age.*
  echo 0 > "$STUB_DIR/attempt"
  RUN_DIR="$TMPDIR/run"
  rm -rf "$RUN_DIR"
  mkdir -p "$RUN_DIR"
  echo "backup" > "$RUN_DIR/poetry.lock.before"
  GH_OUTPUT="$RUN_DIR/gh_output"
  : > "$GH_OUTPUT"
}

invoke_resolve() {
  RC=0
  (
    cd "$RUN_DIR"
    STUB_DIR="$STUB_DIR" PATH="$STUB_DIR/bin:$PATH" \
      GITHUB_OUTPUT="$GH_OUTPUT" GITHUB_STEP_SUMMARY="$RUN_DIR/summary" \
      python3 "$SCRIPT" "$RUN_DIR/poetry.lock.before" 7
  ) > "$RUN_DIR/log" 2>&1 || RC=$?
}

# Clean success on the first attempt.
run_resolve
cp "$TMPDIR/clean.txt" "$STUB_DIR/out.1"
invoke_resolve
check "clean success exits 0" "0" "$RC"
check "clean success waives nothing" "waived=" "$(cat "$GH_OUTPUT")"
check "clean success runs once" "1" "$(cat "$STUB_DIR/attempt")"
check "cooldown days passed through" "7" "$(cat "$STUB_DIR/age.1")"

# The metakernel case: fail once, then succeed with metakernel waived.
run_resolve
cp "$TMPDIR/cooldown.txt" "$STUB_DIR/out.1"
echo 1 > "$STUB_DIR/code.1"
cp "$TMPDIR/clean.txt" "$STUB_DIR/out.2"
invoke_resolve
check "cooldown conflict exits 0 after retry" "0" "$RC"
check "cooldown conflict runs twice" "2" "$(cat "$STUB_DIR/attempt")"
check "first attempt has no exclude list" "" "$(cat "$STUB_DIR/exclude.1")"
check "retry excludes only metakernel" "metakernel" "$(cat "$STUB_DIR/exclude.2")"
check "waived output names the version" "waived=metakernel==1.0.7" "$(cat "$GH_OUTPUT")"

# The exclude env var must be set explicitly on every attempt, including the
# first, so an ambient value from the workflow environment can never leak
# through unwaived. Without this, a stray POETRY_SOLVER_MIN_RELEASE_AGE_EXCLUDE
# set at the job level would be silently honored on attempt 1.
run_resolve
cp "$TMPDIR/clean.txt" "$STUB_DIR/out.1"
RC=0
(
  cd "$RUN_DIR"
  STUB_DIR="$STUB_DIR" PATH="$STUB_DIR/bin:$PATH" \
    GITHUB_OUTPUT="$GH_OUTPUT" GITHUB_STEP_SUMMARY="$RUN_DIR/summary" \
    POETRY_SOLVER_MIN_RELEASE_AGE_EXCLUDE="ambient-leftover" \
    python3 "$SCRIPT" "$RUN_DIR/poetry.lock.before" 7
) > "$RUN_DIR/log" 2>&1 || RC=$?
check "ambient exclude env var is overridden on first attempt" "" "$(cat "$STUB_DIR/exclude.1")"

# Waiving one package exposes a second.
cat > "$TMPDIR/chain.txt" <<'EOF'
Resolving dependencies...
Source (PyPI): The following package versions were ignored due to solver.min-release-age=7
Source (PyPI): widget: 2.0.0

Because thing depends on widget (>=2.0.0) which doesn't match any versions, version solving failed.
EOF
run_resolve
cp "$TMPDIR/cooldown.txt" "$STUB_DIR/out.1"
echo 1 > "$STUB_DIR/code.1"
cp "$TMPDIR/chain.txt" "$STUB_DIR/out.2"
echo 1 > "$STUB_DIR/code.2"
cp "$TMPDIR/clean.txt" "$STUB_DIR/out.3"
invoke_resolve
check "chained conflict exits 0" "0" "$RC"
check "chained conflict accumulates excludes" "metakernel,widget" "$(cat "$STUB_DIR/exclude.3")"

# Genuine conflict: fail immediately, no retry.
run_resolve
cp "$TMPDIR/genuine.txt" "$STUB_DIR/out.1"
echo 1 > "$STUB_DIR/code.1"
invoke_resolve
check "genuine conflict exits 1" "1" "$RC"
check "genuine conflict does not retry" "1" "$(cat "$STUB_DIR/attempt")"

genuine_log_has_cap_note=0
grep -qi "attempt cap" "$RUN_DIR/log" && genuine_log_has_cap_note=1
check "genuine conflict error does not mention the attempt cap" "0" "$genuine_log_has_cap_note"

# Attempt cap: a new culprit every round.
run_resolve
for n in 1 2 3 4 5 6; do
  sed "s/metakernel/pkg$n/g" "$TMPDIR/cooldown.txt" > "$STUB_DIR/out.$n"
  echo 1 > "$STUB_DIR/code.$n"
done
invoke_resolve
check "attempt cap exits 1" "1" "$RC"
check "attempt cap stops at 5" "5" "$(cat "$STUB_DIR/attempt")"

cap_log_has_cap_note=0
grep -qi "attempt cap" "$RUN_DIR/log" && cap_log_has_cap_note=1
check "attempt cap exhaustion is called out in the error text" "1" "$cap_log_has_cap_note"

exit $FAIL
