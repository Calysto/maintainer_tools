#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/get_poetry_version.py"
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

cat > "$TMPDIR/pinned.yaml" <<'EOF'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: trailing-whitespace

  - repo: https://github.com/python-poetry/poetry
    rev: 2.4.3
    hooks:
      - id: poetry-check
      - id: poetry-lock
EOF

check "pinned hook version" \
  "2.4.3" \
  "$(python3 "$SCRIPT" "$TMPDIR/pinned.yaml")"

cat > "$TMPDIR/no-poetry.yaml" <<'EOF'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: trailing-whitespace
EOF

check "no poetry hook -> empty" \
  "" \
  "$(python3 "$SCRIPT" "$TMPDIR/no-poetry.yaml")"

cat > "$TMPDIR/quoted.yaml" <<'EOF'
repos:
  - repo: "https://github.com/python-poetry/poetry.git"
    rev: '2.3.0'
    hooks:
      - id: poetry-check
EOF

check "quoted repo url and rev" \
  "2.3.0" \
  "$(python3 "$SCRIPT" "$TMPDIR/quoted.yaml")"

check "missing file -> empty" \
  "" \
  "$(python3 "$SCRIPT" "$TMPDIR/does-not-exist.yaml")"

exit $FAIL
