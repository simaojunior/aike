---
name: bugfix
description: "Bug hunter. Reproduces bugs with failing tests (RED), then fixes with TDD. Accepts a prompt, issue URL, or bug description. Use when: bugfix, fix bug, debug, broken, regression, failing, doesn't work, fix this."
---

# Bugfix

Bug hunter for the Aike umbrella (Elixir/Phoenix/Ecto/Oban KYC APIs and the
`aike_vision` OCR stack). Reproduces the bug with a failing test, then fixes it with
strict TDD. Focused and surgical.

## Usage

- `/bugfix` — asks what's broken
- `/bugfix <prompt>` — fix from description
- `/bugfix <url>` — fix from a GitHub issue
- `/bugfix <path>` — fix from a bug report file

## Workflow

### Phase 1: Understand the Bug

**No arguments:** ask "What's broken? Describe the bug, paste an issue URL, or
point me to a report." **Wait** for the response.

**Prompt:** use as the bug description.
**URL:** `gh issue view <number> --json title,body --jq '.title + "\n\n" + .body'`
**File path:** read the file.

Restate the bug:

> My understanding: {what's broken, when it happens, expected vs actual}
>
> Is that right? Anything else I should know?

**Wait.** Confirm before proceeding.

### Phase 2: Scout the Bug

Explore the area where the bug lives (an `Explore` agent for a wider sweep, or
read directly):

- Read the relevant source: Peri schema, controller, context, `*Repo`, worker stage,
  engine, extractor or `aike_vision` module
- Read the existing tests for that area
- Trace the data/control flow through the bug
- Check `git log` for recent changes that might have introduced it

Report:

> - **Where it happens:** {file(s), function(s), line(s)}
> - **Root cause hypothesis:** {what's wrong and why}
> - **Existing test coverage:** {what's tested, what's missing}
> - **Recent changes:** {suspicious commits, or "nothing recent"}
>
> Does this match what you're seeing?

**Wait.** The user may have more context.

### Phase 3: Reproduce with a Failing Test

**The most important phase. Do not skip. Do not rush.**

Write a test that **fails right now** because of the bug.

Rules:
- It fails for the **right reason** (the actual bug, not a setup error)
- It's **minimal** — tests only the broken behavior
- It describes the **expected** behavior
- Name it clearly: `test "correct behavior that is currently broken"`
- HTTP bugs: call the endpoint and assert status and error `code`. Pipeline bugs:
  drain the Oban queues or `perform_job/2`. OCR bugs: hand-built OCR lines or a
  synthetic image built in the test
- **Never** reproduce with a real personal document in the repository. If the bug only
  shows on a real document, run it locally from outside the repo and build a synthetic
  fixture with the same structure for the test

> Reproduction test:
>
> ```
> {test_code}
> ```
>
> This proves: {broken behavior} · Expected: {...} · Actual: {...}
>
> Write it?

**Wait.** The user may adjust the test.

Write it, run it, **confirm RED**:

```bash
cd apps/<app> && mix test test/<file>.exs:LINE
```

> RED — {error / assertion failure}

**If it passes unexpectedly:** it doesn't reproduce the bug. Investigate. Ask the
user after 3 failed attempts.

### Phase 4: Fix (GREEN)

Write the **minimum code** to make the failing test pass. Don't refactor
unrelated code, don't add features, don't fix other bugs you spot (note them).
Stay surgical. If the bug is a mis-mapped error, the fix may touch
`KycCore.HttpErrors`, `AikeHttp.Problem` and `docs/api-errors.md`. If it changes engine
or extractor output, bump its version string.

Run the test. **Confirm GREEN.**

### Phase 5: Check for Collateral

Run the gate:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
mix run --no-start scripts/check_boundaries.exs
```

If other tests break, the fix introduced a regression — adjust it.

> Full gate: {pass/fail}. {details if any breakage}

### Phase 6: Refactor (if needed)

Only if the fix is ugly or the area needs cleanup: clean up, re-run tests,
confirm GREEN. Keep it minimal — this is a bugfix, not a rewrite.

### Phase 7: Commit

Stage only the changed files. Commit with:

```
fix(<scope>): <what was fixed>
```

No Co-Authored-By. No AI mentions. See `.claude/rules/git.md`.

## Multiple Bugs

If the input describes several bugs: list them, ask which to tackle first, fix
one at a time (full cycle each), commit each separately.

## Iron Rules

1. **No fix without a failing test.** It must prove the bug before you touch
   production code
2. **Persist on RED.** If you can't reproduce it in a test, dig deeper — don't
   skip to the fix
3. **Minimum fix.** Smallest change that passes. No scope creep
4. **Run the full gate** (format, compile, credo, test, boundaries)
5. **One bug at a time.** Don't batch
6. **Ask when stuck.** Can't reproduce after 3 attempts → ask for more context
7. **Note but don't fix** other bugs you find along the way
