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
# Fake `poetry` on PATH: attempt N prints out.N, exits with code.N, records
# the exclude list it was given to exclude.N, and -- if lock.$N exists --
# overwrites poetry.lock with it (simulating a resolution that changed
# locked versions; resolve_lock.py itself resets poetry.lock to the backup
# before every attempt, so with no lock.$N the file is just left as-is,
# i.e. identical to the backup, meaning "nothing changed").
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
[ -f "$STUB_DIR/lock.$N" ] && cp "$STUB_DIR/lock.$N" poetry.lock
[ -f "$STUB_DIR/code.$N" ] && exit "$(cat "$STUB_DIR/code.$N")"
exit 0
EOF
chmod +x "$STUB_DIR/bin/poetry"

# Reset stub state and run resolve_lock.py in a scratch working directory.
# Sets: RC, GH_OUTPUT, RUN_DIR.
run_resolve() {
  rm -f "$STUB_DIR"/out.* "$STUB_DIR"/code.* "$STUB_DIR"/exclude.* "$STUB_DIR"/age.* "$STUB_DIR"/lock.*
  echo 0 > "$STUB_DIR/attempt"
  RUN_DIR="$TMPDIR/run"
  rm -rf "$RUN_DIR"
  mkdir -p "$RUN_DIR"
  cat > "$RUN_DIR/poetry.lock.before" <<'LOCK'
[[package]]
name = "metakernel"
version = "1.0.5"

[[package]]
name = "widget"
version = "1.9.0"
LOCK
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
check "clean success waives nothing" "$(printf 'waived=\ndowngrades=')" "$(cat "$GH_OUTPUT")"
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
check "waived output names the version" \
  "$(printf 'waived=metakernel==1.0.7\ndowngrades=')" "$(cat "$GH_OUTPUT")"

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

# Regression for numbered derivations: Poetry's mixology/failure.py prefixes
# every line with "(N) " or with padding spaces when the conflict graph has a
# diamond, so no line starts with "Because " at column 0. The gate must still
# recognize the explanation once it starts, or a waivable cooldown conflict
# turns into a hard failure.
cat > "$TMPDIR/numbered.txt" <<'EOF'
Updating dependencies
Resolving dependencies...
Source (PyPI): The following package versions were ignored due to solver.min-release-age=7
Source (PyPI): metakernel: 1.0.6, 1.0.7

(1) Because metakernel (>=1.0) depends on alpha (>=1.0)
 and beta (>=1.0) depends on alpha (>=1.0), metakernel is forbidden.
(2) So, because gamma (>=1.0) depends on delta (>=1.0), left is forbidden.
EOF

check "numbered derivations are still recognized as the failure explanation" \
  "metakernel==1.0.7" \
  "$(culprits "$TMPDIR/numbered.txt")"

# --- Silent downgrade guard --------------------------------------------
# Reproduces the real-world bug: `poetry update --lock` exits 0 (no error,
# no cooldown message at normal verbosity -- that only appears at -vv) but
# quietly relocks a package to an OLDER version than what was already
# locked, because the true latest version fell inside the release-age
# cooldown window. resolve_lock.py must notice this from the lock file
# diff alone and retry with that package's cooldown waived.
cat > "$TMPDIR/downgrade_1.txt" <<'EOF'
Updating dependencies
Resolving dependencies...
Writing lock file
EOF

run_resolve
cp "$TMPDIR/downgrade_1.txt" "$STUB_DIR/out.1"
cat > "$STUB_DIR/lock.1" <<'EOF'
[[package]]
name = "metakernel"
version = "1.0.4"

[[package]]
name = "widget"
version = "1.9.0"
EOF
cp "$TMPDIR/downgrade_1.txt" "$STUB_DIR/out.2"
cat > "$STUB_DIR/lock.2" <<'EOF'
[[package]]
name = "metakernel"
version = "1.0.5"

[[package]]
name = "widget"
version = "1.9.0"
EOF
invoke_resolve
check "silent downgrade exits 0 after retry" "0" "$RC"
check "silent downgrade runs twice" "2" "$(cat "$STUB_DIR/attempt")"
check "silent downgrade retry waives only the regressed package" \
  "metakernel" "$(cat "$STUB_DIR/exclude.2")"
check "silent downgrade waived output names the pre-downgrade version" \
  "$(printf 'waived=metakernel==1.0.5\ndowngrades=')" "$(cat "$GH_OUTPUT")"

downgrade_log_has_warning=0
grep -q "were locked to an OLDER version" "$RUN_DIR/log" && downgrade_log_has_warning=0
grep -q "Release-age cooldown waived for: metakernel" "$RUN_DIR/log" && downgrade_log_has_warning=1
check "waived-cooldown warning is printed for the regressed package" "1" "$downgrade_log_has_warning"

# A downgrade that persists even after its cooldown is waived is NOT the
# cooldown's fault -- some other constraint moved. resolve_lock.py must
# accept the resolution (not block automation or loop to the attempt cap)
# but call it out clearly instead of silently waiving forever.
run_resolve
cp "$TMPDIR/downgrade_1.txt" "$STUB_DIR/out.1"
cat > "$STUB_DIR/lock.1" <<'EOF'
[[package]]
name = "metakernel"
version = "1.0.4"

[[package]]
name = "widget"
version = "1.9.0"
EOF
cp "$TMPDIR/downgrade_1.txt" "$STUB_DIR/out.2"
cp "$STUB_DIR/lock.1" "$STUB_DIR/lock.2"
invoke_resolve
check "unexplained downgrade still exits 0" "0" "$RC"
check "unexplained downgrade does not loop past the retry" "2" "$(cat "$STUB_DIR/attempt")"
check "unexplained downgrade output records it separately from waivers" \
  "$(printf 'waived=metakernel==1.0.5\ndowngrades=metakernel==1.0.5')" "$(cat "$GH_OUTPUT")"

unexplained_log_has_warning=0
grep -q "were locked to an OLDER version than before, even with the release-age cooldown waived" "$RUN_DIR/log" \
  && unexplained_log_has_warning=1
check "unexplained-downgrade warning is printed" "1" "$unexplained_log_has_warning"

exit $FAIL
