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

exit $FAIL
