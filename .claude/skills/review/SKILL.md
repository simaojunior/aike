---
name: review
description: "Deep code review — Elixir/Phoenix/Ecto/Oban idioms, umbrella boundaries, security and personal data, OCR performance. Launches 3 parallel specialist reviewers + a plan-critique gate. Use when: review, review this, code review, check this code, review my changes, is this good, techdebt, code smells."
---

# Code Review — Parallel Specialists + Plan-Critique Gate

**Reviews current changes in the Aike umbrella for quality, security and performance.
Three parallel specialist agents, aggregated findings, and a plan critique before
presenting fixes.**

## Workflow

### Phase 1: Diff

```bash
git diff main...HEAD
git diff main...HEAD --stat
```

If there are uncommitted changes instead, use `git diff` / `git diff --staged`.
Note which apps are touched (`apps/<app>/`, `config/`, `docs/`, `flake.nix`).

### Phase 2: Parallel review

Launch the **3 specialist agents in parallel** — one message with 3 Agent tool calls.

Give each agent the full diff and the list of changed files (they read each in full plus
neighbors).

| Agent | subagent_type | Mandate |
|-------|---------------|---------|
| Quality | `quality-reviewer` | Elixir idioms, boundaries, error contract, engine versioning, docs, tests |
| Security | `security-reviewer` | Tenant isolation, scopes, personal-data leaks, file/process handling, exhaustion |
| Performance | `performance-reviewer` | OCR CPU cost, limits/timeouts, memory, queries, queues |

### Phase 3: Aggregate

1. **Merge** into Critical / Important / Minor / Positive (security Critical/High →
   Critical, Medium → Important, Low → Minor; performance High → Important unless it
   breaks a hot path under peak load)
2. **Deduplicate** the same `file:line`
3. **Tag** each finding: `[quality]`, `[security]`, `[perf]`
4. **Cap**: max 5 Critical, 7 Important, 3 Minor
5. **Verdict**: any Critical/Important → "Needs fixes"; else "Clean with suggestions"

### Phase 4: Plan + critique

**If Critical or Important findings exist:**

1. Build a numbered fix plan: `1. [severity][source] file:line — proposed fix`
2. Launch a **`Plan` agent** to stress-test it against the diff: over-engineering, gaps,
   conflicts, broken behavior, ordering. It returns fixes to DROP, ADD, MODIFY
3. Incorporate the critique and present the adjusted plan

**If only Minor findings**: present the review directly.

### Phase 5: Present

```markdown
## Code Review — {branch}

**Diff**: {files} changed, {ins}+, {del}-  ·  Apps: {list}

### Critical
1) [security] **Issue**: ...
   **Location**: `file:line`
   **Fix**: ...

### Important
### Minor
### Positive

### Verdict
[ ] Clean — ready for `/open-pr`
[x] Needs fixes — see plan below

## Fix Plan (critique-adjusted)
1. [Critical] `file:line` — fix
```

### Phase 6: Implement (after approval)

Implement fixes in plan order with TDD, then run the gate:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
mix run --no-start scripts/check_boundaries.exs
```

## Pipeline

```
/po <prompt> → issue → /dev <issue> → /review → commit → /open-pr
```
