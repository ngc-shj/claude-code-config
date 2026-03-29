---
name: explore
description: "Deep codebase exploration and Q&A. Searches and analyzes code structure, traces call chains, and explains how things work. Use this skill when: asked to explain how something works; asked to find all usages or callers; asked to understand codebase architecture; asked to trace data flow or control flow."
---

# Explore Skill

Deep codebase exploration and Q&A using local LLM for file discovery and Sonnet for detailed analysis.

---

## Step 1: Classify the Query

Determine the exploration type from the user's question:

| Query pattern | Type | Strategy |
|--------------|------|----------|
| "How does X work?" | explanation | Trace implementation, explain flow |
| "Find all callers/usages of Y" | usage-search | Grep + call chain tracing |
| "What is the architecture of Z?" | architecture | Directory structure + key file analysis |
| "Where is X defined/configured?" | location | Targeted file search |
| "How does data flow from A to B?" | data-flow | Trace through layers |

## Step 2: Local LLM File Discovery (Zero Claude Tokens)

Use local LLM to extract search keywords from the user's question:

```bash
echo "[user's question]" | bash ~/.claude/hooks/ollama-utils.sh generate-slug
```

Then use shell tools for initial file discovery (zero Claude tokens):

```bash
# Search for relevant files using keywords (use appropriate file types for the project)
grep -rl "[keyword]" .
# Or use glob patterns for structural exploration
find src/ -type f | head -50
# For architecture queries, get an overview of shared utilities
bash ~/.claude/hooks/scan-shared-utils.sh
```

For larger codebases, use local LLM to build a relevance map:

```bash
# Pipe discovered file contents for relationship analysis
bash ~/.claude/hooks/pre-review.sh code
```

If Ollama is unavailable, proceed to Step 3 with shell-only discovery results.

## Step 3: Sonnet Deep Analysis (Sub-agent)

Launch a Sonnet sub-agent for detailed code tracing:

```
You are a senior engineer performing codebase exploration.

Query type: [explanation/usage-search/architecture/location/data-flow]
User's question: [original question]

Initial file discovery:
[File list and/or local LLM analysis]

Task:
1. Read the most relevant files from the discovery results
2. Based on query type:
   - explanation: Trace the implementation step by step, explain each layer
   - usage-search: Find all callers, build a dependency graph
   - architecture: Map the directory structure, identify key patterns
   - location: Pinpoint the exact file, line, and context
   - data-flow: Trace data through each transformation layer
3. Follow references to related files (imports, function calls, type definitions)
4. Build a clear, structured answer with file:line references

Output format:
- Start with a one-paragraph summary
- Then provide detailed explanation with code references
- End with a relationship diagram (ASCII) if applicable
```

If sub-agents are unavailable, perform the analysis directly.

## Step 4: Synthesize and Present

Review Sonnet's analysis for completeness and accuracy:
- **Verify referenced files exist**: For each file:line reference in the output, confirm the file exists and the line content matches the claim. Remove or correct stale references.
- **Verify function/type existence**: For each named function, type, or constant, grep to confirm it exists at the stated location. Sub-agents may hallucinate names or locations.
- Fill in any gaps the sub-agent may have missed
- Resolve any ambiguities

Present the answer to the user with:
- Clear structure (summary → details → diagram)
- Clickable file:line references (verified to exist)
- Follow-up suggestions for deeper exploration
