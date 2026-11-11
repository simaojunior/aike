---
description: ExUnit and TDD conventions for the Aike umbrella
globs: ["apps/**/test/**/*.exs"]
alwaysApply: false
---

# Testing Conventions

## Running tests

Run inside `nix develop` (Tesseract, Poppler, Python, OpenCV) with Postgres up
(`docker compose up -d postgres`).

```bash
mix test                                        # whole umbrella, from the root
cd apps/document_ocr && mix test                # one app
mix test test/pipeline_test.exs:42              # one test, from the app directory
```

Test databases: `MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate` from the
root creates and migrates the OCR, biometrics and backoffice databases.

## Gate before commit

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
mix run --no-start scripts/check_boundaries.exs
```

`mix quality` runs format, compile, credo and dialyzer.

## TDD cycle

1. **RED**: write the test for the correct behavior; run it; confirm it fails for the
   right reason
2. **GREEN**: the minimum code to pass
3. **REFACTOR**: clean up while green

- The test defines correct behavior. Never change a test to match a wrong implementation
- Every `with`/`case` branch and catch-all needs a test that fails without it

## Conventions

- Tests live in `apps/<app>/test/`. There is no `test/support`; small helpers are private
  functions in the test module
- Repo tests check out the Ecto sandbox (`Ecto.Adapters.SQL.Sandbox.checkout/1`)
- Tests that change `Application` env are `async: false` and restore it in `on_exit`
- Test engines are small modules implementing the behaviour (`TestRGOCR`,
  `TestEngineOverloaded`), registered in the engine registry for the test
- Oban runs in `testing: :manual`: drain queues (`Oban.drain_queue/1`) or call
  `perform_job/2`

## HTTP tests

- Build a `conn`, call the endpoint (`DocumentOcrWeb.Endpoint.call/2`), assert status,
  headers and decoded body
- Assert the error `code` clients depend on, not only the status
- Assert auth boundaries: missing or wrong scope is rejected

## Privacy in tests

- **Never** commit a real document or real personal data. Build synthetic images and PDFs
  in the test (Pillow script via `System.cmd("python3", ...)`) with Naruto-universe names
  ("NARUTO UZUMAKI", company "Konoha") and the test CPF `529.982.247-25`
- Assert that secrets and document content do not leak into logs or error bodies
  (`capture_log/1` and `refute log =~ ...`)

## OCR tests

- Integration tests run the real Tesseract on synthetic fixtures; keep fixtures large and
  clean enough to be stable across Tesseract versions
- Extractor rules are unit-tested with hand-built OCR lines (`text`, `confidence`,
  `bbox`, `source`)
- Accuracy on real documents is measured outside the suite, with authorized samples kept
  out of Git (`scripts/load_classifier.exs` for throughput)

## Edge cases to test

- Missing or empty fields, invalid enums, wrong country
- Oversized, empty or malformed uploads; multi-page PDFs
- Idempotency key reuse with a different body
- Stale `run_id`, retries exhausted, cancelled documents
- Overload (`503` + `Retry-After`) and engine failures without data leaks
