"""Merge a repository's .markdown_link_config.json with markdown-link-check defaults.

Writes a complete markdown-link-check configuration to ``--output``. The defaults
ignore github.com and nbviewer.org links, retry on HTTP 429, and treat 200, 206,
and 403 as alive.

A user config at ``--user-config`` is merged shallowly: its keys override the
defaults, except ``ignorePatterns``, which is the union of the default and user
patterns (defaults first, de-duplicated). A missing user config is not an error.
"""

import argparse
import json
import sys

DEFAULT_CONFIG = {
    "ignorePatterns": [
        {"pattern": "^https://github.com"},
        {"pattern": "^https://nbviewer.org/"},
        {"pattern": "^https://nbviewer.jupyter.org/"},
    ],
    "retryOn429": True,
    "aliveStatusCodes": [200, 206, 403],
}


def load_user_config(path: str) -> dict:
    """Load the user config, returning an empty dict when the file is absent."""
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError as error:
        sys.exit(f"ERROR: {path} is not valid JSON: {error}")
    if not isinstance(data, dict):
        sys.exit(f"ERROR: {path} must contain a JSON object")
    return data


def is_ignore_pattern(entry: object) -> bool:
    """Return True for a {'pattern': <str>} object, the only shape MLC accepts."""
    return isinstance(entry, dict) and isinstance(entry.get("pattern"), str)


def merge_config(user: dict) -> dict:
    """Shallow-merge user settings over the defaults, unioning ignorePatterns."""
    merged = {**DEFAULT_CONFIG, **user}

    user_patterns = user.get("ignorePatterns", [])
    if not isinstance(user_patterns, list) or not all(
        is_ignore_pattern(entry) for entry in user_patterns
    ):
        sys.exit("ERROR: ignorePatterns must be a list of {'pattern': <string>} objects")

    patterns = list(DEFAULT_CONFIG["ignorePatterns"])
    seen = {json.dumps(entry, sort_keys=True) for entry in patterns}
    for entry in user_patterns:
        key = json.dumps(entry, sort_keys=True)
        if key not in seen:
            patterns.append(entry)
            seen.add(key)
    merged["ignorePatterns"] = patterns

    return merged


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user-config", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    merged = merge_config(load_user_config(args.user_config))
    text = json.dumps(merged, indent=2)
    with open(args.output, "w", encoding="utf-8") as handle:
        handle.write(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
