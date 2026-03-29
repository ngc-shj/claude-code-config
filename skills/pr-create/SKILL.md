---
name: pr-create
description: "Create a pull request with auto-generated description. Summarizes changes via local LLM, generates PR body via Sonnet, then creates the PR after user approval. Use this skill when: asked to create a PR; asked to submit changes for review; asked to open a pull request."
---

# PR Create Skill

Creates a pull request with an auto-generated description using local LLM for summarization and Sonnet for PR body composition.

---

## Step 1: Gather Context (Shell Only, Zero Claude Tokens)

```bash
# Confirm branch and ensure not on main
git branch --show-current

# Get change summary
git diff main...HEAD --stat

# Get commit history
git log main...HEAD --oneline

# Check for review artifacts (plan, review log, deviation log, code review log)
ls ./docs/archive/review/*-plan.md ./docs/archive/review/*-review.md \
   ./docs/archive/review/*-deviation.md ./docs/archive/review/*-code-review.md 2>/dev/null
```

If on main branch, ask the user for the target branch or create one.

Ensure all changes are committed before proceeding.

## Step 2: Local LLM Analysis (Zero Claude Tokens)

Summarize changes and classify the PR type:

```bash
# Summarize the diff
git diff main...HEAD | bash ~/.claude/hooks/ollama-utils.sh summarize-diff

# Classify changes
git diff main...HEAD --name-only | bash ~/.claude/hooks/ollama-utils.sh classify-changes
```

If Ollama is unavailable, proceed to Step 3 without pre-analysis.

## Step 3: Sonnet PR Body Generation (Sub-agent)

Launch a Sonnet sub-agent to compose the PR body:

```
You are a technical writer creating a pull request description.

Change type: [feature/fix/refactor/docs/test/chore from classify-changes]

Diff summary (from local LLM):
[summarize-diff output, or "None"]

Commit history:
[git log output]

Deviation log (if exists):
[deviation log contents, or "None"]

Code review log (if exists):
[code review log contents — include resolved finding count and any remaining items, or "None"]

Task:
Generate a PR body in this format:

## Summary
[2-4 bullet points describing what changed and why]

## Changes
[Grouped list of changes by area/component]

## Test plan
[How to verify these changes — infer from commits and test files]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Guidelines:
- Keep the summary concise and focused on "why"
- Group related changes together
- Test plan should be actionable checkboxes
- Use the deviation log to explain any unexpected changes
```

If sub-agents are unavailable, compose the PR body directly.

## Step 4: Review, Approve, and Create

Present the draft PR to the user:

```
=== PR Draft ===
Title: [short title from change type + summary]
Base: main
Head: [current branch]

[PR body]
```

After user approval (allow editing the title and body):

```bash
gh pr create --title "[title]" --body "$(cat <<'EOF'
[PR body]
EOF
)"
```

Report the PR URL to the user.
