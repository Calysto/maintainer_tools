"""Run `poetry update --lock` under a release-age cooldown.

When the cooldown blocks every version satisfying a constraint, waive it for
those packages and retry. When the cooldown lets resolution "succeed" by
silently regressing a package to an older version than what was already
locked, waive it and retry too -- Poetry only logs suppressed versions at
-vv, so a quiet downgrade is otherwise invisible in normal output. Any other
failure stays a failure.
"""

import os
import re
import shutil
import subprocess
import sys

try:
    import tomllib
except ImportError:
    import tomli as tomllib  # type: ignore[no-redef]

MAX_ATTEMPTS = 5

COOLDOWN_HEADER = "were ignored due to solver.min-release-age"
SUPPRESSED_RE = re.compile(r"^Source \([^)]+\): (?P<pkg>[A-Za-z0-9._-]+): (?P<versions>.+)$")
NAME_RE = re.compile(r"[A-Za-z0-9._-]+")
# Poetry's mixology/failure.py numbers each derivation when the conflict
# graph has a diamond, prefixing lines with "(N) " or with padding spaces
# instead of starting flush with "Because ".
BECAUSE_RE = re.compile(r"^(?:\(\d+\)|\s)*Because ")

# Best-effort PEP 440-ish sort key. Numeric release segments compare as
# integers, everything else compares as text. This is not a full PEP 440
# parser -- pre/post/dev-release ordering can be wrong -- but it is good
# enough to catch the common case this guards against: a plain release
# version regressing to an older plain release version.
_VERSION_TOKEN_RE = re.compile(r"\d+|[A-Za-z]+")


def normalize(name: str) -> str:
    """Normalize a package name per PEP 503."""
    return re.sub(r"[-_.]+", "-", name).lower()


def version_key(version: str) -> tuple:
    """Sort key for best-effort version comparison. See module docstring caveat."""
    return tuple(
        (0, int(tok)) if tok.isdigit() else (1, tok)
        for tok in _VERSION_TOKEN_RE.findall(version)
    )


def load_locked_versions(path: str) -> dict[str, str]:
    """Map each normalized package name to its locked version."""
    with open(path, "rb") as f:
        data = tomllib.load(f)
    return {normalize(pkg["name"]): pkg["version"] for pkg in data.get("package", [])}


def find_downgrades(before: dict[str, str], after: dict[str, str]) -> dict[str, str]:
    """Return packages whose locked version regressed, mapped to the old version.

    A regression here is the signal that matters: whether it was actually
    caused by the release-age cooldown or by some other constraint change,
    Poetry does not tell us anything at normal verbosity. Waiving the
    cooldown and retrying is the right response if it *was* the cooldown; if
    it wasn't, the retry reproduces the same version and the caller treats
    that as confirmation the regression is unrelated to the cooldown.
    """
    downgraded = {}
    for name, old_version in before.items():
        new_version = after.get(name)
        if new_version is None:
            continue
        if version_key(new_version) < version_key(old_version):
            downgraded[name] = old_version
    return downgraded


def parse_suppressed(output: str) -> dict[str, str]:
    """Map each normalized package name to the highest version the cooldown hid.

    Poetry lists suppressed versions in ascending order. This only appears in
    Poetry's output when resolution fails outright and it explains why, so it
    complements (but cannot replace) find_downgrades, which is what catches a
    "successful" resolution that quietly picked an older version.
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


def resolve(
    lock_backup: str, min_age_days: str
) -> tuple[bool, dict[str, str], bool, dict[str, str]]:
    """Resolve the lock, waiving the cooldown for packages that block it.

    Returns whether it resolved, the packages waived, whether the attempt cap
    ran out, and any downgrades that persisted even after being waived (i.e.
    regressions the cooldown wasn't responsible for, surfaced for a human to
    look at rather than treated as a failure).
    """
    before = load_locked_versions(lock_backup)
    excluded: dict[str, str] = {}
    retried_for_downgrade: set[str] = set()
    unexplained_downgrades: dict[str, str] = {}

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
            downgrades = find_downgrades(before, load_locked_versions("poetry.lock"))
            # Only chase downgrades we haven't already tried waiving: if we
            # excluded a package for this exact reason last attempt and it
            # regressed again anyway, the cooldown isn't the cause -- stop
            # retrying it and report it instead of looping to the cap.
            new_downgrades = {
                name: version
                for name, version in downgrades.items()
                if name not in retried_for_downgrade
            }
            still_downgraded = {
                name: version
                for name, version in downgrades.items()
                if name in retried_for_downgrade
            }
            unexplained_downgrades.update(still_downgraded)
            if not new_downgrades:
                return True, excluded, False, unexplained_downgrades
            retried_for_downgrade.update(new_downgrades)
            excluded.update(new_downgrades)
            continue

        culprits = find_culprits(output, set(excluded))
        if not culprits:
            return False, excluded, False, unexplained_downgrades
        excluded.update(culprits)

    return False, excluded, True, unexplained_downgrades


def report(excluded: dict[str, str], unexplained_downgrades: dict[str, str]) -> None:
    """Write the waived packages and any unresolved downgrades to the step
    output, annotation, and summary."""
    waived = ",".join(f"{name}=={version}" for name, version in sorted(excluded.items()))
    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a") as f:
            f.write(f"waived={waived}\n")
            downgrades_str = ",".join(
                f"{name}=={version}" for name, version in sorted(unexplained_downgrades.items())
            )
            f.write(f"downgrades={downgrades_str}\n")

    if excluded:
        detail = ", ".join(f"{name} {version}" for name, version in sorted(excluded.items()))
        print(
            f"::warning::Release-age cooldown waived for: {detail}. "
            "Their locked versions have NOT met the configured cooldown."
        )

    if unexplained_downgrades:
        detail = ", ".join(
            f"{name} (was {version})" for name, version in sorted(unexplained_downgrades.items())
        )
        print(
            f"::warning::These packages were locked to an OLDER version than before, "
            f"even with the release-age cooldown waived, so the cooldown was not the "
            f"cause -- review the resolution: {detail}"
        )

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            if excluded:
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
            if unexplained_downgrades:
                f.write("## Unresolved downgrades\n\n")
                f.write(
                    "These packages resolved to a version **older** than what was already "
                    "locked, and waiving the release-age cooldown for them did not change "
                    "that -- so the cooldown was not the cause. This may be a legitimate "
                    "constraint change elsewhere in the dependency graph, but it's worth "
                    "checking by hand before merging. Versions below are what was locked "
                    "before this update.\n\n"
                )
                for name, version in sorted(unexplained_downgrades.items()):
                    f.write(f"- `{name}` was `{version}`\n")
                f.write("\n")


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: resolve_lock.py <lock-backup> <min-release-age-days>", file=sys.stderr)
        sys.exit(2)
    resolved, excluded, cap_exhausted, unexplained_downgrades = resolve(sys.argv[1], sys.argv[2])
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
    report(excluded, unexplained_downgrades)


if __name__ == "__main__":
    main()
