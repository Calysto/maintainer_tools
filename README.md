# maintainer_tools

Reusable GitHub Actions for Calysto packages. All actions are available via the `v1` floating tag:

```yaml
uses: calysto/maintainer_tools/actions/<name>@v1
```

The `v1` tag always points to the latest stable commit and is updated manually via the [Update v1 Tag](.github/workflows/update-v1-tag.yml) workflow.

---

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

---

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

---

### `release`

Runs `base-setup`, bumps the package version, updates `CHANGELOG.md`, commits the changes, creates a GitHub release, then bumps to the next `.dev` version. Supports dry-run mode for testing.

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
- uses: calysto/maintainer_tools/actions/base-setup@v1
- uses: calysto/maintainer_tools/actions/release@v1
  with:
    version: ${{ inputs.version }}
    dry_run: "false"
    app_id: ${{ vars.APP_ID }}
    app_private_key: ${{ secrets.APP_PRIVATE_KEY }}
    ref: ${{ github.ref_name }}
```

---

### `test-minimum-versions`

Pins all dependencies to their minimum allowed versions (as declared in `pyproject.toml`) and runs the test suite. Assumes `base-setup` has already run.

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

---

### `test-sdist`

Downloads the `Packages` artifact produced by `hynek/build-and-inspect-python-package`, unpacks the sdist, and runs the test suite from within it. Assumes `base-setup` has already run.

**Inputs**

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `command` | No | `"just test"` | Command to run the test suite from within the unpacked sdist directory. |

**Usage**

```yaml
- uses: actions/checkout@v6
- uses: calysto/maintainer_tools/actions/base-setup@v1
- uses: calysto/maintainer_tools/actions/test-sdist@v1
  with:
    command: "just test"
```

---

## Tag Management

The `v1` floating tag is maintained manually. After merging stable changes, run the **Update v1 Tag** workflow from the Actions tab. It will:

1. Delete the existing `v1` tag locally and remotely
2. Re-create `v1` at the current `HEAD`
3. Push the updated tag

This requires a GitHub App with `contents: write` permission configured in the `release` environment (`APP_ID` variable and `APP_PRIVATE_KEY` secret).
