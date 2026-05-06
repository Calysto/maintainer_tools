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

### `pre-commit-autoupdate`

Installs [prek](https://prek.j178.dev), runs `prek auto-update` with a configurable cooldown, and opens a pull request with the changes. Optionally generates a GitHub App token for authenticated pushes.

**Inputs**

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `app-id` | No | `""` | GitHub App ID for authenticated pushes. Falls back to `github.token` if not provided. |
| `app-private-key` | No | `""` | GitHub App private key for authenticated pushes. |
| `cooldown-days` | No | `"7"` | Minimum release age in days before updating to a new version. |
| `branch` | No | `"pre-commit-autoupdate"` | Branch name for the autoupdate pull request. |
| `labels` | No | `"maintenance"` | Labels to apply to the pull request. |
| `dry-run` | No | `"false"` | If `"true"`, passes `--dry-run` to `gh pr create` (no PR is actually opened). |

**Usage**

```yaml
- uses: actions/checkout@v6
  with:
    persist-credentials: false
- uses: calysto/maintainer_tools/actions/pre-commit-autoupdate@v1
  with:
    app-id: ${{ vars.APP_ID }}
    app-private-key: ${{ secrets.APP_PRIVATE_KEY }}
```

Typically used in a scheduled workflow:

```yaml
on:
  schedule:
    - cron: '0 9 * * 1'  # Every Monday at 9am

permissions:
  pull-requests: write

jobs:
  autoupdate:
    runs-on: ubuntu-latest
    environment: release
    steps:
      - uses: actions/checkout@v6
        with:
          persist-credentials: false
      - uses: calysto/maintainer_tools/actions/pre-commit-autoupdate@v1
        with:
          app-id: ${{ vars.APP_ID }}
          app-private-key: ${{ secrets.APP_PRIVATE_KEY }}
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

### `pre-commit-run`

Installs [prek](https://prek.j178.dev) and runs pre-commit hooks with environment caching.

**Inputs**

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `extra-args` | No | `"--all-files --hook-stage manual"` | Extra arguments passed to `prek run`. |

**Usage**

```yaml
- uses: actions/checkout@v6
  with:
    persist-credentials: false
- uses: calysto/maintainer_tools/actions/pre-commit-run@v1
```

Typically used in a workflow triggered on `push` and `pull_request` events:

```yaml
jobs:
  pre-commit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          persist-credentials: false
      - uses: calysto/maintainer_tools/actions/pre-commit-run@v1
```

Pass `extra-args` to run only on changed files (e.g. in a PR context):

```yaml
- uses: calysto/maintainer_tools/actions/pre-commit-run@v1
  with:
    extra-args: "--from-ref ${{ github.event.pull_request.base.sha }} --to-ref HEAD"
```

______________________________________________________________________

### `release`

Bumps the package version, updates `CHANGELOG.md`, commits the changes, creates a GitHub release, then bumps to the next `.dev` version. Supports dry-run mode for testing. Requires `base-setup` to run before this action.

**Inputs**

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `version` | Yes | — | Version to release: a version number (e.g. `1.0.0rc4`) or one of: `patch`, `minor`, `major`, `prepatch`, `preminor`, `premajor`, `prerelease`. |
| `dry_run` | No | `"false"` | If `"true"`, creates a draft release then deletes it and does not push changes. |
| `app_id` | No | `""` | GitHub App ID for authenticated pushes (not required for dry runs). |
| `app_private_key` | No | `""` | GitHub App private key (not required for dry runs). |
| `changelog_body` | No | `""` | Custom release notes to use instead of the auto-generated changelog. See [Providing custom release notes](#providing-custom-release-notes). |
| `ref` | Yes | — | Branch to push commits back to (ignored when `dry_run` is `"true"`). |

**Outputs**

| Name | Description |
|------|-------------|
| `tag` | The release tag created (e.g. `v0.3.5`), or the commit SHA on a dry run. |

**Usage**

```yaml
- uses: actions/checkout@v6
- uses: calysto/maintainer_tools/actions/base-setup@v1
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
      - uses: calysto/maintainer_tools/actions/base-setup@v1
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

**Providing custom release notes**

By default the action auto-generates the changelog from PR titles and labels. Pass `changelog_body` to supply your own release notes instead.

The GitHub Actions web UI only provides a single-line text field, so pasting multi-line markdown directly will have its newlines stripped by the browser. There are two ways to work around this:

- **Recommended — use the CLI.** `gh workflow run` accepts real newlines:

  ```bash
  gh workflow run release.yml \
    -f version=patch \
    -f changelog_body="## Highlights

  MetaKernel 1.0 is a major release.

  ## New Features

  - DisplayData() for raw MIME bundle display (#211)"
  ```

- **Use `\n` escape sequences in the web UI.** The action converts literal `\n` strings to real newlines, so you can type or paste a single-line string:

  ```
  ## Highlights\n\nMetaKernel 1.0 is a major release.\n\n## New Features\n\n- DisplayData() for raw MIME bundle display (#211)
  ```

______________________________________________________________________

### `test-minimum-versions`

Pins all dependencies to their minimum allowed versions (as declared in `pyproject.toml`) and runs the test suite. Requires `base-setup` to run before this action.

**Inputs**

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `command` | No | `"just test"` | Command to run the test suite. |

**Usage**

```yaml
- uses: actions/checkout@v6
- uses: calysto/maintainer_tools/actions/base-setup@v1
- uses: calysto/maintainer_tools/actions/test-minimum-versions@v1
  with:
    command: "just test"
```

______________________________________________________________________

### `test-sdist`

Downloads the `Packages` artifact produced by `hynek/build-and-inspect-python-package`, unpacks the sdist, and runs the test suite from within it. Requires `base-setup` to run before this action.

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
      - uses: calysto/maintainer_tools/actions/base-setup@v1
      - uses: calysto/maintainer_tools/actions/test-sdist@v1
        with:
          command: "just test"
```

______________________________________________________________________

### `codeql`

Initializes CodeQL and performs security analysis for a given language. Wraps `github/codeql-action/init` and `github/codeql-action/analyze`.

**Inputs**

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `language` | Yes | — | Language to analyze (e.g. `python`, `actions`, `javascript-typescript`). |
| `build-mode` | No | `"none"` | Build mode: `none`, `autobuild`, or `manual`. |

**Usage**

```yaml
- uses: actions/checkout@v6
  with:
    persist-credentials: false
- uses: calysto/maintainer_tools/actions/codeql@v1
  with:
    language: python
    build-mode: none
```

Typically used in a scheduled CodeQL workflow with a language matrix:

```yaml
on:
  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]
  schedule:
    - cron: '44 18 * * 3'

jobs:
  analyze:
    name: Analyze (${{ matrix.language }})
    if: github.event_name != 'schedule' || github.repository == 'your-org/your-repo'
    runs-on: ubuntu-latest
    permissions:
      security-events: write
      packages: read
      actions: read
      contents: read
    strategy:
      fail-fast: false
      matrix:
        include:
          - language: actions
            build-mode: none
          - language: python
            build-mode: none
    steps:
      - uses: actions/checkout@v6
        with:
          persist-credentials: false
      - uses: calysto/maintainer_tools/actions/codeql@v1
        with:
          language: ${{ matrix.language }}
          build-mode: ${{ matrix.build-mode }}
```

______________________________________________________________________

### `zizmor`

Runs [zizmor](https://woodruffw.github.io/zizmor/) GitHub Actions security analysis. If the calling repository does not have a `.github/zizmor.yml` config file, a bundled default config is used that pins `actions/*` and `calysto/maintainer_tools/*` references to a version tag.

**Inputs**

None.

**Usage**

```yaml
- uses: actions/checkout@v6
  with:
    persist-credentials: false
- uses: calysto/maintainer_tools/actions/zizmor@v1
```

Typically used in a workflow triggered on `push` and `pull_request` events:

```yaml
jobs:
  zizmor:
    runs-on: ubuntu-latest
    permissions:
      security-events: write
    steps:
      - uses: actions/checkout@v6
        with:
          persist-credentials: false
      - uses: calysto/maintainer_tools/actions/zizmor@v1
```

To customize the rules, add a `.github/zizmor.yml` to your repository — it will be used instead of the bundled default.

______________________________________________________________________

## Tag Management

The `v1` floating tag is updated automatically as part of the release workflow. After a stable release (any version without pre-release markers like `a`, `b`, `rc`, or `dev`), the `update-v1-tag` job will:

1. Delete the existing `v1` tag locally and remotely
1. Re-create `v1` at the release commit
1. Push the updated tag

Pre-release versions (e.g. `1.0.0a1`, `1.0.0rc2`) will not update the `v1` tag.
