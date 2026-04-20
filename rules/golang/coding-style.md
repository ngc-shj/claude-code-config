---
name: golang-coding-style
description: Go-specific coding style — extends common/coding-style.md
scope: Go sources
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---

# Go Coding Style

Extends [common/coding-style.md](../common/coding-style.md). Go idioms override some common guidance — noted below.

## Formatting and idiom

- `gofmt` / `goimports` are authoritative. Style is not debatable in Go.
- Follow [Effective Go](https://go.dev/doc/effective_go) and the [Google Go Style Guide](https://google.github.io/styleguide/go/). When idiom conflicts with common rules, idiom wins.

## Mutability (override)

- Go's zero values and pointer receivers mean the common "default to immutability" rule is softened. Mutating through a pointer receiver is idiomatic — do not fight it by over-copying.
- Value receivers for small, read-only types; pointer receivers for anything that mutates or is expensive to copy. Be consistent per type.

## Errors

- Return `error` as the last return value. Do not panic for recoverable errors.
- Wrap with `%w` to preserve the chain: `fmt.Errorf("reading config: %w", err)`.
- Check `errors.Is` / `errors.As` — not string matching on `err.Error()`.
- Do not write `if err != nil { return err }` ladders that lose context. Wrap or annotate.

## Interfaces

- Define interfaces at the consumer, not the producer. A package exports concrete types; the caller defines the interface it needs.
- Keep interfaces small — 1 to 3 methods. Larger interfaces signal missing decomposition.

## Concurrency

- Share by communicating — channels and goroutines, not shared locks, when the shape of the problem allows.
- Every goroutine has a clear termination path. Leaks compound silently.
- Use `context.Context` as the first parameter for anything that does I/O or may cancel. Never store a context in a struct.

## Naming

- Exported names are short and capitalized. Do not stutter (`user.User` is redundant — prefer `user.Account`).
- Package names are lowercase, no underscores, no plurals.

## Tooling

- Run `go vet ./...` and the project's test command before marking work complete.
