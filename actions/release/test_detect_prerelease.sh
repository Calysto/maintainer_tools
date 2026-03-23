#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/detect_prerelease.py"
FAIL=0

check() {
  actual=$(python3 "$SCRIPT" "$1")
  if [ "$actual" = "$2" ]; then
    echo "OK: $1 → $actual"
  else
    echo "FAIL: $1 → $actual (expected $2)"
    FAIL=1
  fi
}

check 1.0.0rc1   true
check prerelease  true
check 1.0.0a1    true
check 1.0.0b2    true
check 1.0.0.dev0 true
check premajor   true
check preminor   true
check prepatch   true
check 1.0.0      false
check patch      false
check minor      false
check major      false

exit $FAIL
