#!/usr/bin/env python3
import os

version = os.environ["VERSION"]
body = os.environ["CHANGELOG_BODY"]

# Normalize body headers so the minimum header level is ### (3 hashes).
# If headers are already at ### or deeper, no change is made.
body_lines = body.split("\n")
header_levels = [len(l) - len(l.lstrip("#")) for l in body_lines if l.startswith("#")]
min_level = min(header_levels) if header_levels else 3
promote_by = max(0, 3 - min_level)
promoted_lines = []
for line in body_lines:
    if line.startswith("#"):
        line = "#" * promote_by + line
    promoted_lines.append(line)
promoted_body = "\n".join(promoted_lines)

with open("CHANGELOG.md") as f:
    lines = f.readlines()
insert_at = None
for i, line in enumerate(lines):
    if line.startswith("# "):
        for j in range(i + 1, len(lines)):
            if lines[j].strip() == "":
                insert_at = j + 1
                break
        break
new_entry = [f"## {version}\n", "\n", promoted_body.rstrip("\n") + "\n", "\n"]
lines[insert_at:insert_at] = new_entry
with open("CHANGELOG.md", "w") as f:
    f.writelines(lines)
