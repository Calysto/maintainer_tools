#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

if ! command -v markdown-link-check >/dev/null 2>&1; then
  npm install -g --silent markdown-link-check@3.15.0
fi

python3 "$HERE/merge_config.py" --user-config "$TMPDIR/absent.json" \
  --output "$TMPDIR/mlc_config.json" >/dev/null

run() {
  markdown-link-check --config "$TMPDIR/mlc_config.json" "$@" >"$TMPDIR/out.txt" 2>&1
}

check_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "OK: $desc"
  else
    echo "FAIL: $desc (expected exit $expected, got $actual)"
    cat "$TMPDIR/out.txt"
    FAIL=1
  fi
}

mkdir -p "$TMPDIR/fx/recursion/sub" "$TMPDIR/fx/ignore/skip" "$TMPDIR/fx/clean"

cat > "$TMPDIR/fx/recursion/top.md" <<'EOF'
# Top

[deep](./sub/deep.md)
EOF
cat > "$TMPDIR/fx/recursion/sub/deep.md" <<'EOF'
# Deep

[missing](./missing.md)
EOF

rc=0
run "$TMPDIR/fx/recursion" || rc=$?
check_exit "dead link in a nested file fails the scan" 1 "$rc"
if grep -q "sub/deep.md" "$TMPDIR/out.txt"; then
  echo "OK: nested file was scanned"
else
  echo "FAIL: nested file was not scanned"
  FAIL=1
fi

cat > "$TMPDIR/fx/ignore/keep.md" <<'EOF'
# Keep

[target](./target.md)
EOF
cat > "$TMPDIR/fx/ignore/target.md" <<'EOF'
# Target
EOF
cat > "$TMPDIR/fx/ignore/skip/dead.md" <<'EOF'
# Dead

[missing](./missing.md)
EOF

rc=0
run -i "$TMPDIR/fx/ignore/skip" "$TMPDIR/fx/ignore" || rc=$?
check_exit "ignore-paths skips a folder containing a dead link" 0 "$rc"

rc=0
run "$TMPDIR/fx/ignore" || rc=$?
check_exit "the same folder fails when not ignored" 1 "$rc"

cat > "$TMPDIR/fx/clean/good.md" <<'EOF'
# Good

[target](./target.md)
[github](https://github.com/does/not/exist)
EOF
cat > "$TMPDIR/fx/clean/target.md" <<'EOF'
# Target
EOF

rc=0
run "$TMPDIR/fx/clean" || rc=$?
check_exit "clean tree passes and default ignorePatterns apply" 0 "$rc"

exit $FAIL
