# maintainer_tools

Reusable GitHub Actions for Calysto packages. All actions are available via the `v1` floating tag:

```yaml
uses: calysto/maintainer_tools/actions/<name>@v1
```

The `v1` tag always points to the latest stable commit and is updated automatically on each stable release.

______________________________________________________________________

## Actions

### `base-setup`

Installs Python, Poetry (with OS-keyed cache), `just`, and project dependencies. This action should be the first step in any job that needs to build or test the package.

**Inputs**

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `python-version` | No | `""` | Python version to use. Defaults to the minimum version from `pyproject.toml`. |

**Usage**

```yaml
- uses: actions/checkout@v6
- uses: calysto/maintainer_tools/actions/base-setup@v1
  with:
    python-version: "3.12"
```

A full test matrix workflow using `hynek/build-and-inspect-python-package` to derive the supported Python versions:

```yaml
jobs:
  build:
    name: Build & inspect package
    runs-on: ubuntu-latest
    outputs:
      supported_python_classifiers_json_array: ${{ steps.baipp.outputs.supported_python_classifiers_json_array }}
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - uses: hynek/build-and-inspect-python-package@v2
        id: baipp

  test:
    name: Test (Python ${{ matrix.python-version }})
    needs: [build]
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        python-version: ${{ fromJSON(needs.build.outputs.supported_python_classifiers_json_array) }}
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - uses: calysto/maintainer_tools/actions/base-setup@v1
        with:
          python-version: ${{ matrix.python-version }}
      - run: just test
```

______________________________________________________________________

### `enforce-label`

Enforces that every PR has at least one of the required labels: `bug`, `enhancement`, `dependencies`, `maintenance`, `documentation`.

**Inputs**

None.

**Usage**

```yaml
- uses: actions/checkout@v6
- uses: calysto/maintainer_tools/actions/enforce-label@v1
```

Typically used in a workflow triggered on `pull_request` events:

```yaml
on:
  pull_request:
    types: [labeled, unlabeled, opened, edited, synchronize]

jobs:
  enforce-label:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: calysto/maintainer_tools/actions/enforce-label@v1
```

______________________________________________________________________

### `release`

Bumps the package version, updates `CHANGELOG.md`, commits the changes, creates a GitHub release, then bumps to the next `.dev` version. Supports dry-run mode for testing. **Runs `base-setup` internally** — do not call `base-setup` before this action.

**Inputs**

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `version` | Yes | — | Version to release: a version number (e.g. `1.0.0rc4`) or one of: `patch`, `minor`, `major`, `prepatch`, `preminor`, `premajor`, `prerelease`. |
| `dry_run` | No | `"false"` | If `"true"`, creates a draft release then deletes it and does not push changes. |
| `app_id` | No | `""` | GitHub App ID for authenticated pushes (not required for dry runs). |
| `app_private_key` | No | `""` | GitHub App private key (not required for dry runs). |
| `ref` | Yes | — | Branch to push commits back to (ignored when `dry_run` is `"true"`). |

**Outputs**

| Name | Description |
|------|-------------|
| `tag` | The release tag created (e.g. `v0.3.5`), or the commit SHA on a dry run. |

**Usage**

```yaml
- uses: actions/checkout@v6
- uses: calysto/maintainer_tools/actions/release@v1
  with:
    version: ${{ inputs.version }}
    dry_run: "false"
    app_id: ${{ vars.APP_ID }}
    app_private_key: ${{ secrets.APP_PRIVATE_KEY }}
    ref: ${{ github.ref_name }}
```

A full release workflow with build and PyPI publish steps:

```yaml
jobs:
  release:
    runs-on: ubuntu-latest
    environment: release
    permissions:
      contents: write
    outputs:
      tag: ${{ steps.release.outputs.tag }}
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - uses: calysto/maintainer_tools/actions/release@v1
        id: release
        with:
          version: ${{ inputs.version }}
          dry_run: ${{ inputs.dry_run }}
          app_id: ${{ vars.APP_ID }}
          app_private_key: ${{ secrets.APP_PRIVATE_KEY }}
          ref: ${{ github.ref_name }}

  build:
    name: Build & verify package
    needs: [release]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ needs.release.outputs.tag }}
          fetch-depth: 0
          persist-credentials: false
      - uses: hynek/build-and-inspect-python-package@v2

  publish:
    needs: [build]
    runs-on: ubuntu-latest
    environment: release
    permissions:
      id-token: write
      attestations: write
    steps:
      - name: Download packages built by build-and-inspect-python-package
        uses: actions/download-artifact@v4
        with:
          name: Packages
          path: dist
      - name: Upload package to Test PyPI
        uses: pypa/gh-action-pypi-publish@v1
        with:
          repository-url: https://test.pypi.org/legacy/
          skip-existing: ${{ inputs.dry_run }}
      - name: Upload package to PyPI
        if: ${{ !inputs.dry_run }}
        uses: pypa/gh-action-pypi-publish@v1
```

______________________________________________________________________

### `test-minimum-versions`

Pins all dependencies to their minimum allowed versions (as declared in `pyproject.toml`) and runs the test suite. **Runs `base-setup` internally** — do not call `base-setup` before this action.

**Inputs**

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `command` | No | `"just test"` | Command to run the test suite. |

**Usage**

```yaml
- uses: actions/checkout@v6
- uses: calysto/maintainer_tools/actions/test-minimum-versions@v1
  with:
    command: "just test"
```

______________________________________________________________________

### `test-sdist`

Downloads the `Packages` artifact produced by `hynek/build-and-inspect-python-package`, unpacks the sdist, and runs the test suite from within it. **Runs `base-setup` internally** — do not call `base-setup` before this action.

**Inputs**

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `command` | No | `"just test"` | Command to run the test suite from within the unpacked sdist directory. |

**Usage**

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hynek/build-and-inspect-python-package@v2

  test-sdist:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: calysto/maintainer_tools/actions/test-sdist@v1
        with:
          command: "just test"
```

______________________________________________________________________

## Tag Management

The `v1` floating tag is updated automatically as part of the release workflow. After a stable release (any version without pre-release markers like `a`, `b`, `rc`, or `dev`), the `update-v1-tag` job will:

1. Delete the existing `v1` tag locally and remotely
1. Re-create `v1` at the release commit
1. Push the updated tag

Pre-release versions (e.g. `1.0.0a1`, `1.0.0rc2`) will not update the `v1` tag.
