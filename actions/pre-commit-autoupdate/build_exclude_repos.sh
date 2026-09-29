#!/usr/bin/env bash
# Print the hook repositories to exclude from `prek update`, one per line.
#
# The configured poetry hook is always printed first, in whatever URL form the
# config uses (https, ssh, with or without a .git suffix). pre-commit-autoupdate
# must never bump the poetry hook: its version is coupled to poetry.lock (via
# base-setup) and is owned by poetry-lock-update. Any extra repositories are
# appended after it.
#
# Usage: build_exclude_repos.sh [config-path] [extra-repo...]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HELPER="$HERE/../base-setup/get_poetry_version.py"

CONFIG="${1:-.pre-commit-config.yaml}"
shift || true

POETRY_REPO=$(python3 "$HELPER" --repo "$CONFIG" 2>/dev/null || true)
if [ -n "$POETRY_REPO" ]; then
  printf '%s\n' "$POETRY_REPO"
fi

for repo in "$@"; do
  if [ -n "$repo" ]; then
    printf '%s\n' "$repo"
  fi
done
