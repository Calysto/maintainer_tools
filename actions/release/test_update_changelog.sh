#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/update_changelog.py"
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

CHANGELOG="$TMPDIR_WORK/CHANGELOG.md"
printf '# Changelog\n\nSome intro text.\n\n## 0.1.0\n\nOld entry.\n' > "$CHANGELOG"

(cd "$TMPDIR_WORK" && VERSION=1.0.0 CHANGELOG_BODY="## Enhancements Made
- new stuff" python3 "$SCRIPT")

if ! grep -q "## 1.0.0" "$CHANGELOG"; then
  echo "FAIL: version header not inserted"
  exit 1
fi

if ! grep -q "### Enhancements Made" "$CHANGELOG"; then
  echo "FAIL: body headers not promoted to ###"
  exit 1
fi

if ! grep -q "## 0.1.0" "$CHANGELOG"; then
  echo "FAIL: old entry missing"
  exit 1
fi

python3 - "$CHANGELOG" <<'EOF'
import sys
with open(sys.argv[1]) as f:
    lines = f.readlines()
idxs = [i for i, l in enumerate(lines) if l.startswith("## ")]
assert len(idxs) >= 2, "expected at least 2 ## headers"
assert idxs[0] < idxs[1], "new entry not before old entry"
EOF

# Test that body headers already at ### are not further promoted
printf '# Changelog\n\nSome intro text.\n\n## 0.1.0\n\nOld entry.\n' > "$CHANGELOG"

(cd "$TMPDIR_WORK" && VERSION=2.0.0 CHANGELOG_BODY="### Enhancements Made
- more stuff" python3 "$SCRIPT")

if grep -q "#### Enhancements Made" "$CHANGELOG"; then
  echo "FAIL: ### headers were over-promoted to ####"
  exit 1
fi

if ! grep -q "### Enhancements Made" "$CHANGELOG"; then
  echo "FAIL: ### headers not preserved"
  exit 1
fi

echo "OK: update_changelog.py"
