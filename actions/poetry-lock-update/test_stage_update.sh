#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/stage_update.sh"
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

setup_repo() {
  rm -rf "$TMPDIR/repo"
  mkdir -p "$TMPDIR/repo"
  cd "$TMPDIR/repo"
  git init -q
  git config user.name test
  git config user.email test@example.com
  git config commit.gpgsign false
  echo "# lock" > poetry.lock
  echo "rev: 2.4.3" > .pre-commit-config.yaml
  git add poetry.lock .pre-commit-config.yaml
  git commit -q -m initial
}

commit_files() {
  git show --pretty=format: --name-only HEAD | grep -v '^$' | sort | tr '\n' ' '
}

# Case 1: both the lock and the hook rev changed -> both committed.
setup_repo
echo "# lock regenerated" > poetry.lock
echo "rev: 2.5.1" > .pre-commit-config.yaml
OUT=$(bash "$SCRIPT")
check "both changed -> reports changed" "changed" "$OUT"
check "both changed -> commits both files" \
  ".pre-commit-config.yaml poetry.lock " \
  "$(commit_files)"

# Case 2: only the hook rev changed -> the config is still committed.
setup_repo
echo "rev: 2.5.1" > .pre-commit-config.yaml
OUT=$(bash "$SCRIPT")
check "hook only -> reports changed" "changed" "$OUT"
check "hook only -> commits the config" \
  ".pre-commit-config.yaml " \
  "$(commit_files)"

# Case 3: nothing changed -> no commit.
setup_repo
BEFORE=$(git rev-parse HEAD)
OUT=$(bash "$SCRIPT")
check "no changes -> reports unchanged" "unchanged" "$OUT"
check "no changes -> no new commit" "$BEFORE" "$(git rev-parse HEAD)"

# Case 4: lock changed and the config file is absent -> no error.
rm -rf "$TMPDIR/repo"
mkdir -p "$TMPDIR/repo"
cd "$TMPDIR/repo"
git init -q
git config user.name test
git config user.email test@example.com
git config commit.gpgsign false
echo "# lock" > poetry.lock
git add poetry.lock
git commit -q -m initial
echo "# lock regenerated" > poetry.lock
OUT=$(bash "$SCRIPT")
check "no config file -> reports changed" "changed" "$OUT"
check "no config file -> commits only the lock" "poetry.lock " "$(commit_files)"

exit $FAIL
