---
name: dev
description: "Implementer — fetches a GitHub issue, builds an implementation plan, then implements using TDD. Use when: implement, build this, code this, add this feature, TDD, test first, red green refactor, pick a task, next task, dev."
---

# Implementer — TDD Engineer

**Fetches a GitHub issue, plans the implementation, then builds it with strict TDD in
the Aike umbrella.**

## Usage

- `/dev <issue_url>` or `/dev <issue_number>` — fetch issue, plan, implement
- `/dev` — ask which issue to implement

## Workflow

### Phase 1: Understand

1. **Fetch the issue**: `gh issue view <number> --json title,body`
2. **Explore** the affected area (an `Explore` agent for a wide sweep): which app,
   context, `*Repo`, schema, Peri schema, controller, JSON view, worker stage, engine or
   `aike_vision` module; existing patterns; current tests
3. **Identify the gap** between current state and the issue
4. **Challenge the PRD** when research shows missing edge cases, a better approach,
   existing code that already solves part of it, or a boundary/privacy/capacity problem

### Phase 1.5: PRD feedback (when needed)

5. Present the findings to the user
6. If the user agrees, run `/po amend <issue_number>` and wait for the amended issue
7. If not, proceed and note the disagreement in the plan

### Phase 2: Plan

8. **Enter plan mode** and design:
   - Ordered, testable increments
   - Files: migration (with `up`/`down` for constraints), schema, context, `*Repo`, Peri
     schema, controller, JSON view, worker stage, engine, config registry, docs
   - **Error contract**: a new error atom needs `KycCore.HttpErrors`, the code in
     `AikeHttp.Problem` and `docs/api-errors.md`
   - **Versioning**: engine or extractor behavior changes need a new version string and
     registry entry
   - **Privacy**: no personal data in logs, errors, job args or fixtures
   - **Capacity**: new CPU work goes through `AikeVision` limiters; count OCR passes
9. Launch a **`Plan` agent** to verify claims against the code, find gaps (tenant
   scoping, untested paths, missing docs), and flag over-engineering
10. Revise and present for approval

### Phase 3: Implement (TDD)

11. Create a branch: `feat/<short-name>`
12. For each task, run RED → GREEN → REFACTOR
13. After all tasks, run `quality-reviewer`; for auth, tenant or personal-data work also
    run `security-reviewer`; for OCR or request-path work also `performance-reviewer`

## The Cycle

### RED — one failing test

```elixir
test "a request without a document names the missing file" do
  response =
    conn(:post, "/v1/extractions", %{"external_id" => "x"})
    |> DocumentOcrWeb.Endpoint.call([])

  assert response.status == 422
  assert [%{"field" => "file"}] = Jason.decode!(response.resp_body)["errors"]
end
```

Run `mix test test/<file>.exs:<line>` from the app directory. **It must fail** for the
right reason. After 3 attempts, ask the user.

### GREEN — minimum code

Follow `.claude/rules/elixir.md` and `.claude/rules/testing.md`. Run the test; **it must
pass**. Fix the implementation, not the test. After 5 attempts, ask the user.

### REFACTOR

Clean the changed code; stay green.

## Iron Rules

1. No production code without a failing test
2. Baby steps; run tests after every change
3. Refactor only when green; one task at a time
4. Escalate, don't spin
5. Never use real personal documents in tests or commits

## Per-task checklist

- [ ] RED → GREEN → REFACTOR for each increment
- [ ] Error contract wired (if a new error path)
- [ ] Version strings bumped (if engine or extractor behavior changed)
- [ ] Docs in `docs/` updated (Portuguese)
- [ ] Gate passes:
      `mix format --check-formatted && mix compile --warnings-as-errors && mix credo --strict && mix test && mix run --no-start scripts/check_boundaries.exs`
- [ ] Commit (see `.claude/rules/git.md`)

## Pipeline

```
/po <prompt> → issue → /dev <issue> → /review → commit → /open-pr
                 ^            |
                 +-- /po amend +
```
