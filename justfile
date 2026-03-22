install:
    poetry install

test:
    poetry run pytest tests/ -v

pre-commit *args:
    poetry run pre-commit run --all-files {{args}}
