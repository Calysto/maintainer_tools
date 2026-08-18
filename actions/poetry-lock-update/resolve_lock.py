"""Run `poetry update --lock` under a release-age cooldown.

When the cooldown blocks the only versions that satisfy a constraint, waive the
cooldown for exactly those packages and retry. Any other resolution failure is
left as a failure.
"""

import re

MAX_ATTEMPTS = 5

COOLDOWN_HEADER = "were ignored due to solver.min-release-age"
SUPPRESSED_RE = re.compile(r"^Source \([^)]+\): (?P<pkg>[A-Za-z0-9._-]+): (?P<versions>.+)$")
NAME_RE = re.compile(r"[A-Za-z0-9._-]+")


def normalize(name: str) -> str:
    """Normalize a package name per PEP 503."""
    return re.sub(r"[-_.]+", "-", name).lower()


def parse_suppressed(output: str) -> dict[str, str]:
    """Map normalized package name to the highest version the cooldown suppressed.

    Poetry lists suppressed versions in ascending order, so the last entry on
    the line is the highest.
    """
    suppressed: dict[str, str] = {}
    in_block = False
    for line in output.splitlines():
        if COOLDOWN_HEADER in line:
            in_block = True
            continue
        if not in_block:
            continue
        match = SUPPRESSED_RE.match(line)
        if match is None:
            in_block = False
            continue
        versions = [v.strip() for v in match.group("versions").split(",") if v.strip()]
        if versions:
            suppressed[normalize(match.group("pkg"))] = versions[-1]
    return suppressed


def parse_blamed(output: str) -> set[str]:
    """Collect normalized package names from everything outside the suppressed blocks."""
    blamed: set[str] = set()
    in_block = False
    for line in output.splitlines():
        if COOLDOWN_HEADER in line:
            in_block = True
            continue
        if in_block:
            if SUPPRESSED_RE.match(line):
                continue
            in_block = False
        blamed.update(normalize(name) for name in NAME_RE.findall(line))
    return blamed


def find_culprits(output: str, already_excluded: set[str]) -> dict[str, str]:
    """Return packages the cooldown suppressed that the solver also blamed."""
    suppressed = parse_suppressed(output)
    blamed = parse_blamed(output)
    return {
        name: version
        for name, version in suppressed.items()
        if name in blamed and name not in already_excluded
    }
