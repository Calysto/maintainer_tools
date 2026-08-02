#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/diff_lock.py"
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

cat > "$TMPDIR/old.lock" <<'EOF'
[[package]]
name = "black"
version = "23.1.0"

[[package]]
name = "flake8"
version = "6.0.0"

[[package]]
name = "requests"
version = "2.31.0"
EOF

cat > "$TMPDIR/new.lock" <<'EOF'
[[package]]
name = "black"
version = "23.3.0"

[[package]]
name = "flake8"
version = "6.0.0"

[[package]]
name = "requests"
version = "2.31.0"

[[package]]
name = "click"
version = "8.1.0"
EOF

ACTUAL=$(python3 "$SCRIPT" "$TMPDIR/old.lock" "$TMPDIR/new.lock")

check "changed version" \
  "- black: \`23.1.0\` → \`23.3.0\`" \
  "$(echo "$ACTUAL" | grep '^- black:')"

check "added package" \
  "- click: added \`8.1.0\`" \
  "$(echo "$ACTUAL" | grep '^- click:')"

check "unchanged package omitted" \
  "" \
  "$(echo "$ACTUAL" | grep '^- flake8:' || true)"

check "line count" \
  "2" \
  "$(echo "$ACTUAL" | grep -c '^-')"

cat > "$TMPDIR/old2.lock" <<'EOF'
[[package]]
name = "urllib3"
version = "2.0.0"
EOF

cat > "$TMPDIR/new2.lock" <<'EOF'
EOF

ACTUAL2=$(python3 "$SCRIPT" "$TMPDIR/old2.lock" "$TMPDIR/new2.lock")
check "removed package" \
  "- urllib3: removed \`2.0.0\`" \
  "$ACTUAL2"

cat > "$TMPDIR/same.lock" <<'EOF'
[[package]]
name = "idna"
version = "3.4"
EOF

ACTUAL3=$(python3 "$SCRIPT" "$TMPDIR/same.lock" "$TMPDIR/same.lock")
check "no changes -> empty output" "" "$ACTUAL3"

exit $FAIL
