#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/merge_config.py"
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

check() {
  local desc="$1"
  local expected="$2"
  local actual_file="$3"
  if python3 -c 'import json,sys; sys.exit(0 if json.loads(sys.argv[1]) == json.load(open(sys.argv[2])) else 1)' \
    "$expected" "$actual_file"; then
    echo "OK: $desc"
  else
    echo "FAIL: $desc"
    echo "  expected: $expected"
    echo "  actual:   $(cat "$actual_file")"
    FAIL=1
  fi
}

check_fails() {
  local desc="$1"
  local user_config="$2"
  if python3 "$SCRIPT" --user-config "$user_config" --output "$TMPDIR/out.json" >/dev/null 2>&1; then
    echo "FAIL: $desc (expected non-zero exit)"
    FAIL=1
  else
    echo "OK: $desc"
  fi
}

DEFAULTS='{"ignorePatterns":[{"pattern":"^https://github.com"},{"pattern":"^https://nbviewer.org/"}],"retryOn429":true,"aliveStatusCodes":[200,206,403]}'

python3 "$SCRIPT" --user-config "$TMPDIR/missing.json" --output "$TMPDIR/out.json" >/dev/null
check "missing user config -> defaults" "$DEFAULTS" "$TMPDIR/out.json"

echo '{}' > "$TMPDIR/empty.json"
python3 "$SCRIPT" --user-config "$TMPDIR/empty.json" --output "$TMPDIR/out.json" >/dev/null
check "empty user config -> defaults" "$DEFAULTS" "$TMPDIR/out.json"

cat > "$TMPDIR/union.json" <<'EOF'
{"ignorePatterns": [{"pattern": "^https://example.com"}]}
EOF
python3 "$SCRIPT" --user-config "$TMPDIR/union.json" --output "$TMPDIR/out.json" >/dev/null
check "user pattern is unioned after defaults" \
  '{"ignorePatterns":[{"pattern":"^https://github.com"},{"pattern":"^https://nbviewer.org/"},{"pattern":"^https://example.com"}],"retryOn429":true,"aliveStatusCodes":[200,206,403]}' \
  "$TMPDIR/out.json"

cat > "$TMPDIR/dupe.json" <<'EOF'
{"ignorePatterns": [{"pattern": "^https://github.com"}]}
EOF
python3 "$SCRIPT" --user-config "$TMPDIR/dupe.json" --output "$TMPDIR/out.json" >/dev/null
check "user pattern matching a default is de-duplicated" \
  '{"ignorePatterns":[{"pattern":"^https://github.com"},{"pattern":"^https://nbviewer.org/"}],"retryOn429":true,"aliveStatusCodes":[200,206,403]}' \
  "$TMPDIR/out.json"

cat > "$TMPDIR/override.json" <<'EOF'
{"retryOn429": false, "timeout": "30s"}
EOF
python3 "$SCRIPT" --user-config "$TMPDIR/override.json" --output "$TMPDIR/out.json" >/dev/null
check "user keys override defaults and add new keys" \
  '{"ignorePatterns":[{"pattern":"^https://github.com"},{"pattern":"^https://nbviewer.org/"}],"retryOn429":false,"aliveStatusCodes":[200,206,403],"timeout":"30s"}' \
  "$TMPDIR/out.json"

echo '{not json' > "$TMPDIR/invalid.json"
check_fails "invalid JSON fails" "$TMPDIR/invalid.json"

echo '[1, 2, 3]' > "$TMPDIR/array.json"
check_fails "non-object user config fails" "$TMPDIR/array.json"

echo '{"ignorePatterns": "nope"}' > "$TMPDIR/bad-patterns.json"
check_fails "non-list ignorePatterns fails" "$TMPDIR/bad-patterns.json"

echo '{"ignorePatterns": ["^https://example.com"]}' > "$TMPDIR/bad-pattern-entries.json"
check_fails "non-object ignorePatterns entry fails" "$TMPDIR/bad-pattern-entries.json"

exit $FAIL
