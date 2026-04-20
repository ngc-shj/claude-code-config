---
name: python-coding-style
description: Python-specific coding style — extends common/coding-style.md
scope: Python sources
paths:
  - "**/*.py"
  - "**/*.pyi"
---

# Python Coding Style

Extends [common/coding-style.md](../common/coding-style.md).

## Formatting and lint

- Follow the project's formatter — usually `black` or `ruff format`. Detect from `pyproject.toml`.
- Follow the project's linter — usually `ruff`, `flake8`, or `pylint`. Do not argue style with the linter; fix the code.
- Sort imports deterministically (`ruff`, `isort`). Group: stdlib, third-party, local.

## Type hints

- Public functions and methods have type hints on parameters and return.
- Use `from __future__ import annotations` or Python 3.10+ union syntax (`X | Y`) — match the codebase.
- Prefer `collections.abc.Mapping`/`Sequence` in signatures over concrete `dict`/`list` when the function does not mutate.

## Data and immutability

- Prefer `@dataclass(frozen=True)` or `NamedTuple` for value objects.
- Prefer comprehensions over `map`/`filter` + `lambda`. Prefer generator expressions when the result is consumed once.

## Errors

- Raise specific exceptions (`ValueError`, `LookupError`, custom subclasses) — not bare `Exception`.
- `except` clauses name the exception type. Bare `except:` and `except Exception:` are almost always wrong.
- Use `raise ... from err` to preserve the cause when re-raising.

## Resource management

- Always use `with` for files, locks, sockets, DB connections.
- For async I/O, use `async with`. Do not mix blocking calls inside async functions.

## Tooling

- Run the project's test and type-check commands. Detect from `pyproject.toml` (`[tool.pytest]`, `[tool.mypy]`, `[tool.pyright]`) or `tox.ini`.
