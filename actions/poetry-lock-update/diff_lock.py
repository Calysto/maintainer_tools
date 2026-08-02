"""Diff two poetry.lock files and print a markdown list of package version changes."""

import sys

try:
    import tomllib
except ImportError:
    import tomli as tomllib  # type: ignore[no-redef]


def load_versions(path: str) -> dict[str, str]:
    with open(path, "rb") as f:
        data = tomllib.load(f)
    return {pkg["name"]: pkg["version"] for pkg in data.get("package", [])}


def diff_versions(old: dict[str, str], new: dict[str, str]) -> list[str]:
    lines = []
    for name in sorted(set(old) | set(new)):
        old_version = old.get(name)
        new_version = new.get(name)
        if old_version == new_version:
            continue
        if old_version is None:
            lines.append(f"- {name}: added `{new_version}`")
        elif new_version is None:
            lines.append(f"- {name}: removed `{old_version}`")
        else:
            lines.append(f"- {name}: `{old_version}` → `{new_version}`")
    return lines


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: diff_lock.py <old.lock> <new.lock>", file=sys.stderr)
        sys.exit(2)
    old = load_versions(sys.argv[1])
    new = load_versions(sys.argv[2])
    for line in diff_versions(old, new):
        print(line)


if __name__ == "__main__":
    main()
