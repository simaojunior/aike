---
description: Elixir/Phoenix/Ecto/Oban patterns, idioms and anti-patterns for the Aike umbrella
globs: ["apps/**/*.ex", "apps/**/*.exs", "config/**/*.exs", "scripts/**/*.exs"]
alwaysApply: false
---

# Elixir / Phoenix Patterns

Aike is an Elixir umbrella of machine-to-machine KYC APIs. No HTML, no LiveView, no
frontend. Each service is a Phoenix JSON API with its own release.

## Apps and boundaries

| App | Role |
|---|---|
| `document_ocr` | Async extraction: `POST /v1/extractions`, Ecto + Oban pipeline (preprocess → ocr → extract → validate → complete) |
| `document_classifier` | Sync, stateless classification: `POST /v1/classifications` |
| `biometrics` | Facematch sessions; own Repo, migrations and database |
| `backoffice` | Companies, users, service accounts, token introspection; own Repo |
| `aike_vision` | OpenCV (`evision`) + Tesseract executable: decode, orientation, crop, OCR, node-wide limiters |
| `aike_storage` | Blobs per owner (`AikeStorage.Owner`: Repo, bucket folder, reference columns); S3/R2 and local adapters |
| `aike_http` | `Problem` error bodies, `Envelope` responses, `Health`, parsers, `ValidateParams` (Peri) |
| `aike_auth` | Service-account introspection plug |
| `aike_observability` | Redaction, request logging, queue metrics |
| `kyc_core` | Shared types, `HttpErrors`, idempotency, `JsonKeyFormatter`, scopes |

- Processing services never depend on each other or on `backoffice`. Shared code goes
  in a shared app. `scripts/check_boundaries.exs` enforces this
- Each service owns its migrations, Repo and database. Never read another service's tables
- Each service with files owns a bucket folder (`DocumentOcr.BlobOwner`,
  `Biometrics.BlobOwner`). Pass the owner to `AikeStorage`; never hardcode service tables
  in a shared app
- Every service must run alone on its own machine: no shared database, no loopback-only
  assumptions. See `docs/deploy.md`

## Control flow

- Multi-clause functions and guards over `if/else` for dispatch; no `unless`
- `with` for `{:ok, _} / {:error, _}` pipelines; translate failures in `else`
- `case` only to match an already computed value; no `case` inside `case`
- Credo `--strict` rejects bodies nested deeper than 2: extract a helper
- `maybe_x(nil)` / `maybe_x(value)` for optional values

## Contexts, schemas, repos

- Controllers call contexts (`Documents`, `Classifications`, `Facematches`). `Repo` calls
  live in the context or a `*Repo` module (`DocumentRepo`), never in controllers
- `use DocumentOcr, :repository` in query modules
- Invariants are enforced in the database too: check constraints, unique indexes,
  composite foreign keys. Validations alone race
- A changed check constraint needs a migration with `up` and `down`

## HTTP layer

- Input validation is a Peri schema in `*Web.Schemas.*Params`, plugged per action with
  `ValidateParams`. Failures are `422 validation` with field errors
- Input and output fields are camelCase (`selfieImage`, `externalId`), in JSON, form-data
  and query strings. Peri schemas declare the camelCase names; `ValidateParams` parses
  them to snake_case for controllers. Never accept or document snake_case fields
- Responses: JSON keys go through `KycCore.JsonKeyFormatter` (camelCase)
- Header names are lowercase in code, tests and docs (`prefer`, `idempotency-key`)
- Controllers use `action_fallback`; never hand-build error JSON

## The error contract

`KycCore.HttpErrors.info/1` maps each domain error atom to `{status, code}` and uses
`Map.fetch!`: an unregistered atom raises on purpose. `AikeHttp.Problem` holds the detail
text of each `code`.

A new `{:error, :reason}` path needs:
1. the atom in `KycCore.HttpErrors`
2. the `code` in `AikeHttp.Problem` (if new)
3. the code in `docs/api-errors.md`
4. a test that asserts the `code`, not only the status

Overload is `503 service_unavailable` with `Retry-After`.

## Auth and tenancy

- Every route sits behind a scope pipeline (`ocr:write`, `ocr:read`, `classifier:write`,
  ...). Scopes are listed in `KycCore.Auth.Scopes`
- The tenant comes from the authenticated service account (`conn.assigns[:company_id]`).
  `app_id` in a payload never overrides it; it is a fallback only with auth disabled
- Every query on tenant data is scoped to the company

## Privacy (non-negotiable)

- Never log, persist in errors, or put in Oban args: document text, CPF, names, birth
  dates, image bytes, tokens. Use `AikeObservability.redact/1`
- Error messages and logs carry codes and IDs only
- Never commit real personal documents. Tests build synthetic fixtures

## Processing pipeline (document_ocr)

- Jobs carry `document_id` and `run_id` only. A stage checks the run is current
- Stages are idempotent: `finished?/2` skips work already done
- Provenance: `pipeline_version`, `ocr_engine`, `ocr_engine_version`, `extractor_version`
  are captured on the document. Changing engine or extractor behavior requires a new
  version string and its registry entry in `config/config.exs`
- A failure that a retry cannot fix ends the document with a clear `error_code`
  (`Processor.fail/3`) instead of exhausting retries

## Engines and adapters

- Engines (OCR, classifier, facematch, storage) are behaviours with a `Fake` for tests
  (`config/test.exs`). Real engines are selected in `config/config.exs`
- An adapter honors the engine version it receives or returns an error; it never silently
  substitutes another model
- OCR CPU work goes through `AikeVision` so the node limits apply
  (`AikeVision.Processes`, `AikeVision.Documents`). See `docs/capacity.md`

## Configuration

- Compile-time defaults in `config/config.exs`; environment-specific overrides in
  `config/runtime.exs`, scoped to the release (`:document_ocr in services`)
- Runtime values from env vars are validated (positive integers, non-empty strings) and
  fail fast at boot

## Typespecs and naming

- `@spec` on public functions; `@type t` on structs
- `String.t()`, `binary()` for bytes, `term()` (not `any()`), `[type()]`
- Descriptive names; no single-letter variables except iterators
- Modules under ~200 lines; extract submodules

## Comments and docs

- No comments in code: no `#` lines or trailing notes in Elixir, Python, config, YAML,
  migrations, scripts or tests. Reasons go in the docs below
- Project docs in `docs/` are Portuguese, in simplified technical writing. Update them
  when a contract, limit or engine changes

### `@moduledoc` on every public module

1. First line: what the module is, in one sentence
2. A short paragraph: its responsibility, main behavior and any non-obvious reason
3. Sections when they apply:
   - `## Configuration`: the config keys, with a `config :app, ...` example
   - `## Properties` / `## Fields`: for schemas and structured results
   - `## Errors`: the error atoms it returns and when
   - `## Examples`: a short code block with the common calls

### `@doc` on every public function

```elixir
@doc """
Reads the text of an image with Tesseract.

## Parameters
  - image: the image to read (`Evision.Mat.t()`)
  - directory: private workspace for temporary files

## Returns
  - `{:ok, words}` with each word's text, confidence and box
  - `{:error, :timeout}` when Tesseract does not finish in time

## Example

    {:ok, words} = AikeVision.Tesseract.words(image, directory, "3")
"""
```

- Summary line, then `## Parameters`, `## Returns` (every tuple) and `## Example` when
  the call is not obvious
- Private functions have no docs and no comments
- Mocks, fixtures and examples use names from the Naruto universe: companies and apps
  ("Konoha", `konoha`, "Akatsuki"), people ("NARUTO UZUMAKI", "SAKURA HARUNO",
  "KUSHINA UZUMAKI") and places ("KONOHAGAKURE"), with the test CPF `529.982.247-25`.
  Never real personal data or the names of real companies

## Anti-patterns

- `Repo` in controllers; one service calling another's modules or tables
- Unregistered error atoms; error JSON built by hand
- Personal data in logs, errors, job args, test fixtures or Git
- Engine behavior changed without a new version string
- Unbounded work per request (no limiter, no timeout)
- `if/else` dispatch, `unless`, nested `case`, deep nesting
- Comments in code
