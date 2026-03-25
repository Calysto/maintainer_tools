"""Verify that the sdist contains test files starting with test_."""

import sys
from pathlib import Path

try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib  # type: ignore[no-redef]
    except ImportError:
        tomllib = None  # type: ignore[assignment]


def get_test_paths() -> list[Path]:
    pyproject = Path("pyproject.toml")
    if tomllib is not None and pyproject.exists():
        with pyproject.open("rb") as f:
            data = tomllib.load(f)
        pytest_cfg = data.get("tool", {}).get("pytest", {})
        ini_options = pytest_cfg.get("ini_options", pytest_cfg)
        testpaths = ini_options.get("testpaths", [])
        if testpaths:
            return [Path(p) for p in testpaths]

    # Fall back to top-level test/ or tests/
    return [p for p in [Path("test"), Path("tests")] if p.is_dir()]


def main() -> None:
    test_paths = get_test_paths()

    if not test_paths:
        print("Error: no 'test' or 'tests' directory found and no testpaths configured")
        sys.exit(1)

    for path in test_paths:
        if list(path.rglob("test_*")):
            return

    paths_str = ", ".join(str(p) for p in test_paths)
    print(f"Error: no files starting with 'test_' found in test directories: {paths_str}")
    sys.exit(1)


if __name__ == "__main__":
    main()
