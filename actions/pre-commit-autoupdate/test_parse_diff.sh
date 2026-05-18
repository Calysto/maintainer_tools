#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/parse_diff.sh"
FAIL=0

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

# Simulate a git diff with three repos using no quotes, single quotes, and double quotes
DIFF=$(cat <<'EOF'
  - repo: https://github.com/pre-commit/pre-commit-hooks
-   rev: v4.4.0
+   rev: v4.5.0
  - repo: https://github.com/psf/black
-   rev: '23.1.0'
+   rev: '23.3.0'
  - repo: https://github.com/PyCQA/flake8
-   rev: "6.0.0"
+   rev: "6.1.0"
EOF
)

ACTUAL=$(echo "$DIFF" | bash "$SCRIPT" -)

check "no-quotes version" \
  "- pre-commit-hooks: \`v4.4.0\` → \`v4.5.0\`" \
  "$(echo "$ACTUAL" | grep pre-commit-hooks)"

check "single-quoted version" \
  "- black: \`23.1.0\` → \`23.3.0\`" \
  "$(echo "$ACTUAL" | grep black)"

check "double-quoted version" \
  "- flake8: \`6.0.0\` → \`6.1.0\`" \
  "$(echo "$ACTUAL" | grep flake8)"

exit $FAIL
