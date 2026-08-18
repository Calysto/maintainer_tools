"""Run `poetry update --lock` under a release-age cooldown.

When the cooldown blocks every version satisfying a constraint, waive it for
those packages and retry. Any other failure stays a failure.
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
# Poetry's mixology/failure.py numbers each derivation when the conflict
# graph has a diamond, prefixing lines with "(N) " or with padding spaces
# instead of starting flush with "Because ".
BECAUSE_RE = re.compile(r"^(?:\(\d+\)|\s)*Because ")


def normalize(name: str) -> str:
    """Normalize a package name per PEP 503."""
    return re.sub(r"[-_.]+", "-", name).lower()


def parse_suppressed(output: str) -> dict[str, str]:
    """Map each normalized package name to the highest version the cooldown hid.

    Poetry lists suppressed versions in ascending order.
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
    """Collect normalized package names from the solver's failure explanation.

    Earlier lines carry Poetry's status output ("Updating dependencies"), whose
    words are themselves real PyPI project names and would register as false
    blames.
    """
    blamed: set[str] = set()
    in_explanation = False
    for line in output.splitlines():
        if not in_explanation:
            if not BECAUSE_RE.match(line):
                continue
            in_explanation = True
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


def resolve(lock_backup: str, min_age_days: str) -> tuple[bool, dict[str, str], bool]:
    """Resolve the lock, waiving the cooldown for packages that block it.

    Returns whether it resolved, the packages waived, and whether the attempt
    cap ran out.
    """
    excluded: dict[str, str] = {}
    for _ in range(MAX_ATTEMPTS):
        shutil.copyfile(lock_backup, "poetry.lock")
        env = dict(os.environ)
        env["POETRY_SOLVER_MIN_RELEASE_AGE"] = min_age_days
        # Always set explicitly, even to "" on the first attempt: an ambient
        # value set at the workflow level must not leak into a resolve that
        # hasn't earned any waivers yet.
        env["POETRY_SOLVER_MIN_RELEASE_AGE_EXCLUDE"] = ",".join(sorted(excluded))
        code, output = run_poetry(env)
        if code == 0:
            return True, excluded, False
        culprits = find_culprits(output, set(excluded))
        if not culprits:
            return False, excluded, False
        excluded.update(culprits)
    return False, excluded, True


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
    print(
        f"::warning::Release-age cooldown waived for: {detail}. "
        "Their locked versions have NOT met the configured cooldown."
    )

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("## Cooldown waived\n\n")
            f.write(
                "No version satisfying the dependency graph was old enough to pass "
                "the release-age cooldown, so it was waived for these packages. "
                "Their locked versions have **not** met the cooldown; review them "
                "as you would any early-release upgrade. Versions below are what "
                "triggered each waiver, and the waiver is package-scoped, so the "
                "solver may have locked something newer.\n\n"
            )
            for name, version in sorted(excluded.items()):
                f.write(f"- `{name}` `{version}`\n")
            f.write("\n")


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: resolve_lock.py <lock-backup> <min-release-age-days>", file=sys.stderr)
        sys.exit(2)
    resolved, excluded, cap_exhausted = resolve(sys.argv[1], sys.argv[2])
    if not resolved:
        if cap_exhausted:
            print(
                f"::error::Resolution did not converge within the {MAX_ATTEMPTS}-attempt cap. "
                "Every attempt surfaced a newly blocked package. Waived so far: "
                + ", ".join(sorted(excluded)),
                file=sys.stderr,
            )
        elif excluded:
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
