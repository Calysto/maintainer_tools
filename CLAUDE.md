# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
just install          # Install dependencies via Poetry
just test             # Run all tests
just test tests/test_foo.py::test_bar  # Run a single test
just pre-commit       # Run pre-commit hooks on all files
just pre-commit --hook-stage=manual   # Also run actionlint on workflow files
```

## Architecture

This repo provides reusable GitHub Actions for Calysto Python packages, consumed via the `v1` floating tag:

```yaml
uses: calysto/maintainer_tools/actions/<name>@v1
```

### Actions

Each action lives in `actions/<name>/action.yml`. The actions are:

- **`base-setup`** — Sets up Python (auto-detects minimum version from `pyproject.toml` if unspecified), Poetry, and `just` with OS-keyed cache. Must be called before `release`, `test-minimum-versions`, and `test-sdist`.
- **`poetry-lock-update`** — Runs `poetry update` under a minimum-release-age cooldown (`POETRY_SOLVER_MIN_RELEASE_AGE`, default 7 days) and opens a pull request with the `poetry.lock` diff, updating an existing open PR on the branch in place instead of opening a duplicate. Requires a GitHub App (`APP_ID` / `APP_PRIVATE_KEY`) for authenticated pushes. Must be called after `base-setup`.
- **`enforce-label`** — Wraps `yogevbd/enforce-label-action`; requires one of: `bug`, `enhancement`, `dependencies`, `maintenance`, `documentation`.
- **`release`** — Full release pipeline: bumps version via Poetry, generates and writes CHANGELOG.md, commits and pushes, creates GitHub release, then bumps to next `.dev` version using `actions/release/bump_dev.py`. Supports dry-run. Requires a GitHub App (`APP_ID` / `APP_PRIVATE_KEY`) for authenticated pushes.
- **`test-minimum-versions`** — Rewrites `pyproject.toml` to pin all deps to their minimum declared versions, then runs the test suite.
- **`test-sdist`** — Downloads the `Packages` artifact from `hynek/build-and-inspect-python-package`, unpacks the sdist, and runs the test suite from within it.

### Release workflow

`.github/workflows/release.yml` orchestrates:

1. **`release`** job — runs `./actions/release`, outputs the new tag
1. **`build-package`** job — checks out the release tag and builds via `hynek/build-and-inspect-python-package` as a release-time sanity check (this package is not published to PyPI)
1. **`update-v1-tag`** job — moves the `v1` floating tag to the new release commit; skipped for pre-releases (tags containing `a`, `b`, `rc`, or `dev`)

`workflow_dispatch` runs use `dry_run: false` by default; scheduled runs always use `dry_run: true`.

### PRs

Always target the upstream repo: `--repo Calysto/maintainer_tools --head <your-github-username>:<branch>`.
