#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/build_exclude_repos.sh"
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

cat > "$TMPDIR/https.yaml" <<'EOF'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0

  - repo: https://github.com/python-poetry/poetry
    rev: 2.5.1
    hooks:
      - id: poetry-lock
EOF

check "https poetry hook is excluded" \
  "https://github.com/python-poetry/poetry" \
  "$(bash "$SCRIPT" "$TMPDIR/https.yaml")"

cat > "$TMPDIR/ssh.yaml" <<'EOF'
repos:
  - repo: git@github.com:python-poetry/poetry.git
    rev: 2.5.1
    hooks:
      - id: poetry-lock
EOF

check "ssh poetry hook is excluded" \
  "git@github.com:python-poetry/poetry.git" \
  "$(bash "$SCRIPT" "$TMPDIR/ssh.yaml")"

cat > "$TMPDIR/quoted.yaml" <<'EOF'
repos:
  - repo: "https://github.com/python-poetry/poetry.git"
    rev: '2.5.1'
    hooks:
      - id: poetry-lock
EOF

check "quoted .git poetry hook is excluded" \
  "https://github.com/python-poetry/poetry.git" \
  "$(bash "$SCRIPT" "$TMPDIR/quoted.yaml")"

cat > "$TMPDIR/no-poetry.yaml" <<'EOF'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
EOF

check "no poetry hook -> only extra repos" \
  "https://example.com/one
https://example.com/two" \
  "$(bash "$SCRIPT" "$TMPDIR/no-poetry.yaml" https://example.com/one https://example.com/two)"

check "poetry hook plus extra repos, poetry first" \
  "https://github.com/python-poetry/poetry
https://example.com/one" \
  "$(bash "$SCRIPT" "$TMPDIR/https.yaml" https://example.com/one)"

check "missing config -> only extra repos" \
  "https://example.com/one" \
  "$(bash "$SCRIPT" "$TMPDIR/does-not-exist.yaml" https://example.com/one)"

exit $FAIL
