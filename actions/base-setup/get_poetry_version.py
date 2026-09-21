"""Print the Poetry version pinned by the poetry hook in .pre-commit-config.yaml.

Exits 0 with no output when no such hook is configured, letting the caller fall
back to the latest Poetry release.
"""

import re
import sys

REPO_RE = re.compile(r"^\s*-\s*repo:\s*(?P<repo>.+?)\s*$")
REV_RE = re.compile(r"^\s*rev:\s*(?P<rev>.+?)\s*$")


def is_poetry_repo(url: str) -> bool:
    return url.rstrip("/").removesuffix(".git").endswith("python-poetry/poetry")


def poetry_rev(path: str) -> str | None:
    current_repo = None
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                line = line.rstrip("\n")
                repo_match = REPO_RE.match(line)
                if repo_match:
                    current_repo = repo_match.group("repo").strip().strip("'\"")
                    continue
                rev_match = REV_RE.match(line)
                if rev_match and current_repo and is_poetry_repo(current_repo):
                    return rev_match.group("rev").strip().strip("'\"")
    except FileNotFoundError:
        return None
    return None


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else ".pre-commit-config.yaml"
    rev = poetry_rev(path)
    if rev:
        print(rev)


if __name__ == "__main__":
    main()
