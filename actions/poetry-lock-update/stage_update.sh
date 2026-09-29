#!/usr/bin/env bash
# Stage and commit the files a lock update touches: poetry.lock plus the hook
# configuration (.pre-commit-config.yaml and/or prek.toml). Assumes the bot
# branch has already been checked out.
#
# Prints "changed" when a commit was created, or "unchanged" when there was
# nothing to commit. Either way it exits 0.
set -euo pipefail

PATHS=(poetry.lock .pre-commit-config.yaml prek.toml)
STAGE=(poetry.lock)
for path in .pre-commit-config.yaml prek.toml; do
  if [ -f "$path" ]; then
    STAGE+=("$path")
  fi
done

if git diff --quiet -- "${PATHS[@]}"; then
  echo "unchanged"
  exit 0
fi

git add "${STAGE[@]}"

if git diff --cached --quiet; then
  echo "unchanged"
  exit 0
fi

git commit -q -m "chore: update poetry.lock"
echo "changed"
