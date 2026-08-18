"""Run `poetry update --lock` under a release-age cooldown.

When the cooldown blocks the only versions that satisfy a constraint, waive the
cooldown for exactly those packages and retry. Any other resolution failure is
left as a failure.
"""

import os
import re
import shutil
import subprocess
import sys

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


def run_poetry(env: dict[str, str]) -> tuple[int, str]:
    """Run the lock update, streaming output to the log and capturing it."""
    proc = subprocess.Popen(
        ["poetry", "update", "--no-interaction", "--lock"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )
    captured = []
    assert proc.stdout is not None
    for line in proc.stdout:
        sys.stdout.write(line)
        captured.append(line)
    sys.stdout.flush()
    return proc.wait(), "".join(captured)


def resolve(lock_backup: str, min_age_days: str) -> tuple[bool, dict[str, str]]:
    """Resolve the lock, waiving the cooldown for packages that block it.

    Returns whether the lock resolved, and the packages that were waived.
    """
    excluded: dict[str, str] = {}
    for _ in range(MAX_ATTEMPTS):
        shutil.copyfile(lock_backup, "poetry.lock")
        env = dict(os.environ)
        env["POETRY_SOLVER_MIN_RELEASE_AGE"] = min_age_days
        if excluded:
            env["POETRY_SOLVER_MIN_RELEASE_AGE_EXCLUDE"] = ",".join(sorted(excluded))
        code, output = run_poetry(env)
        if code == 0:
            return True, excluded
        culprits = find_culprits(output, set(excluded))
        if not culprits:
            return False, excluded
        excluded.update(culprits)
    return False, excluded


def report(excluded: dict[str, str]) -> None:
    """Write the waived packages to the step output, annotation, and summary."""
    waived = ",".join(f"{name}=={version}" for name, version in sorted(excluded.items()))
    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a") as f:
            f.write(f"waived={waived}\n")

    if not excluded:
        return

    detail = ", ".join(f"{name} {version}" for name, version in sorted(excluded.items()))
    print(f"::warning::Release-age cooldown waived for: {detail}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("## Cooldown waived\n\n")
            f.write("Required by a constraint in `pyproject.toml`:\n\n")
            for name, version in sorted(excluded.items()):
                f.write(f"- `{name}` `{version}`\n")
            f.write("\n")


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: resolve_lock.py <lock-backup> <min-release-age-days>", file=sys.stderr)
        sys.exit(2)
    resolved, excluded = resolve(sys.argv[1], sys.argv[2])
    if not resolved:
        if excluded:
            print(
                "::error::Resolution failed after waiving the release-age cooldown for: "
                + ", ".join(sorted(excluded)),
                file=sys.stderr,
            )
        else:
            print(
                "::error::Resolution failed and the release-age cooldown was not the cause.",
                file=sys.stderr,
            )
        sys.exit(1)
    report(excluded)


if __name__ == "__main__":
    main()
