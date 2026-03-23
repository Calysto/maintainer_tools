#!/usr/bin/env python3
import os

version = os.environ["VERSION"]
body = os.environ["CHANGELOG_BODY"]
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
new_entry = [f"## {version}\n", "\n", body.rstrip("\n") + "\n", "\n"]
lines[insert_at:insert_at] = new_entry
with open("CHANGELOG.md", "w") as f:
    f.writelines(lines)
