install:
    poetry install

test *args:
    poetry run pytest tests/ -v {{args}}

pre-commit *args:
    poetry run pre-commit run --all-files {{args}}
