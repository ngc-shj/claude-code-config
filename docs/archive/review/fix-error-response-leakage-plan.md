# Fix Error Response Leakage in Hook Scripts

## Objective

Prevent Ollama error responses from leaking code fragments or request content to stderr, which ends up in Claude's conversation context.

## Requirements

- `ollama-utils.sh`: When Ollama returns non-200, do not output response body content (may contain echoed request with code)
- `pre-review.sh`: Same fix for its independent curl call
- Maintain existing graceful degradation behavior (warning message + exit 0)
- Do not suppress legitimate operational warnings (e.g., "Ollama unavailable")

## Technical approach

Replace `head -5 "$response_file" >&2` with a safe error message that includes only the HTTP status code, not the response body.

## Implementation steps

1. `hooks/ollama-utils.sh` line 55: Replace `head -5 "$tmpdir/response.json" >&2` with an error message that includes the HTTP status code but not the response body
2. `hooks/pre-review.sh` line ~189: Same fix
3. Verify no other scripts have the same pattern (confirmed: only these 2 files via `grep -r 'head.*response.*>&2' hooks/`)

## Testing strategy

- Run `pre-review.sh code` against a real diff — verify normal operation unchanged
- Simulate Ollama error (e.g., wrong model name) — verify no response body leaks to stderr

## Considerations & constraints

- The response body was previously output for debugging. After this change, debugging Ollama errors requires checking Ollama server logs directly.
- This is a config-only repo with no test framework — manual verification only.

## User operation scenarios

- Normal operation: Ollama available, returns 200 → no change in behavior
- Ollama returns 500 (model load failure): Warning printed with HTTP code only, no response body
- Ollama unavailable (connection refused): Existing "Ollama unavailable" path, no change
