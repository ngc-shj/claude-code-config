---
name: pr-create
description: "Create a pull request with auto-generated description. Summarizes changes and generates PR body via local LLM (gpt-oss:120b), then creates the PR after user approval. Use this skill when: asked to create a PR; asked to submit changes for review; asked to open a pull request."
---

# PR Create Skill

Creates a pull request with an auto-generated description using local LLM for summarization and PR body composition.

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

## Step 3: Local LLM PR Body Generation (Zero Claude Tokens)

```bash
# Aggregate context for generate-pr-body: everything on stdin as one section.
{
  echo "=== COMMIT LOG ==="
  git log main...HEAD --oneline
  echo
  echo "=== DIFF STAT ==="
  git diff main...HEAD --stat
  echo
  for f in ./docs/archive/review/*-plan.md ./docs/archive/review/*-review.md \
           ./docs/archive/review/*-deviation.md ./docs/archive/review/*-code-review.md; do
    [ -f "$f" ] || continue
    echo "=== $f ==="
    cat "$f"
    echo
  done
} | bash ~/.claude/hooks/ollama-utils.sh generate-pr-body
```

If Ollama is unavailable, compose the PR body directly as fallback.

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
