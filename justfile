install:
    poetry sync --only dev

test *args:
    poetry sync --only test
    poetry run pytest tests/ -v {{args}}

lint *args:
    poetry sync --only dev
    poetry run pre-commit run --all-files {{args}}

lint-all *args:
    poetry sync --only dev
    poetry run pre-commit run --all-files --hook-stage manual {{args}}
