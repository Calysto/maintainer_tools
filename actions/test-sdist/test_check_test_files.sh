#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/check_test_files.py"
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

check() {
  local desc="$1"
  local dir="$2"
  local expect_exit="$3"
  actual_exit=0
  python3 "$SCRIPT" 2>/dev/null || actual_exit=$?
  if [ "$actual_exit" -eq "$expect_exit" ]; then
    echo "OK: $desc"
  else
    echo "FAIL: $desc (exit $actual_exit, expected $expect_exit)"
    FAIL=1
  fi
}

run_in() {
  local dir="$1"; shift
  ( cd "$dir" && "$@" )
}

# Case: tests/ dir with test_ file → pass
D="$TMPDIR/case1"
mkdir -p "$D/tests"
touch "$D/tests/test_foo.py"
run_in "$D" check "tests/test_foo.py" "$D" 0

# Case: test/ dir with test_ file → pass
D="$TMPDIR/case2"
mkdir -p "$D/test"
touch "$D/test/test_bar.py"
run_in "$D" check "test/test_bar.py" "$D" 0

# Case: tests/ dir but no test_ files → fail
D="$TMPDIR/case3"
mkdir -p "$D/tests"
touch "$D/tests/conftest.py"
run_in "$D" check "tests/ with no test_ files" "$D" 1

# Case: no test dir at all → fail
D="$TMPDIR/case4"
mkdir -p "$D"
run_in "$D" check "no test directory" "$D" 1

# Case: pyproject.toml testpaths with test_ file → pass
D="$TMPDIR/case5"
mkdir -p "$D/src/tests"
touch "$D/src/tests/test_things.py"
cat > "$D/pyproject.toml" <<'EOF'
[tool.pytest.ini_options]
testpaths = ["src/tests"]
EOF
run_in "$D" check "testpaths = [src/tests] with test_ file" "$D" 0

# Case: [tool.pytest] (not ini_options) testpaths with test_ file → pass
D="$TMPDIR/case7"
mkdir -p "$D/src/tests"
touch "$D/src/tests/test_things.py"
cat > "$D/pyproject.toml" <<'EOF'
[tool.pytest]
testpaths = ["src/tests"]
EOF
run_in "$D" check "[tool.pytest] testpaths with test_ file" "$D" 0

# Case: pyproject.toml testpaths but no test_ files → fail
D="$TMPDIR/case6"
mkdir -p "$D/src/tests"
touch "$D/src/tests/conftest.py"
cat > "$D/pyproject.toml" <<'EOF'
[tool.pytest.ini_options]
testpaths = ["src/tests"]
EOF
run_in "$D" check "testpaths = [src/tests] with no test_ files" "$D" 1

exit $FAIL
