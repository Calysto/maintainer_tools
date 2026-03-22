install:
    poetry install

test:
    pytest tests/ -v

pre-commit *args:
    pre-commit run --all-files {{args}}
