"""Print the Poetry version pinned by the poetry hook in .pre-commit-config.yaml.

Reads the config file (or a path given as an argument) and locates the hook
whose repository is python-poetry/poetry. Prints the pinned ``rev`` by default,
or the repository URL when ``--repo`` is passed.

Exits 0 with no output when no such hook is configured, letting the caller fall
back to the latest Poetry release.
"""

import argparse
import re

REPO_RE = re.compile(r"^\s*-\s*repo:\s*(?P<repo>.+?)\s*$")
REV_RE = re.compile(r"^\s*rev:\s*(?P<rev>.+?)\s*$")


def is_poetry_repo(url: str) -> bool:
    return url.rstrip("/").removesuffix(".git").endswith("python-poetry/poetry")


def find_poetry_hook(path: str) -> tuple[str | None, str | None]:
    """Return (repo_url, rev) for the poetry hook, or (None, None)."""
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
                    return current_repo, rev_match.group("rev").strip().strip("'\"")
    except FileNotFoundError:
        return None, None
    return None, None


def poetry_rev(path: str) -> str | None:
    return find_poetry_hook(path)[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", default=".pre-commit-config.yaml")
    parser.add_argument(
        "--repo",
        action="store_true",
        help="Print the poetry repository URL instead of the pinned revision",
    )
    args = parser.parse_args()

    repo, rev = find_poetry_hook(args.path)
    value = repo if args.repo else rev
    if value:
        print(value)


if __name__ == "__main__":
    main()
