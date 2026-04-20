---
name: python-testing
description: Python testing conventions — extends common/testing.md
scope: Python test files
paths:
  - "**/test_*.py"
  - "**/*_test.py"
  - "**/tests/**/*.py"
---

# Python Testing

Extends [common/testing.md](../common/testing.md).

## Framework

- Default to `pytest` unless the project uses `unittest`. Do not mix styles within one module.
- Use fixtures (`@pytest.fixture`) over setUp/tearDown inheritance. Scope fixtures to the narrowest level (`function` default).

## Parametrization

- Use `@pytest.mark.parametrize` instead of a loop inside one test. Parametrization gives each case its own failure line.
- Name parameter sets with `ids=` when the values alone are not self-explanatory.

## Mocking

- Prefer `monkeypatch` for environment, module attributes, and simple function replacement.
- Use `unittest.mock.patch` with `autospec=True` so mock signatures match the real callable. Without autospec, typo'd method names silently pass.
- Do not patch the module where the object is defined. Patch where it is *looked up* (`module_under_test.external_call`).

## Async

- Use `pytest-asyncio` or `anyio`. Mark async tests explicitly per the project convention.
- Never call `asyncio.run` inside a test that the framework is already running.

## Fixtures and state

- Do not use module-level mutable state. Use fixtures.
- Clean up temporary files via `tmp_path` fixture — never `/tmp` directly.
