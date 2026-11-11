---
name: po
description: "Product Owner — scans the codebase and creates or amends GitHub issues with a PRD. Use when: PRD, feature, issue, create issue, amend issue, what should we build, plan feature, design feature, scope, requirements, user story."
---

# Product Owner — Aike

**Scan the codebase, write a PRD, and open a GitHub issue.**

Aike is an Elixir umbrella of machine-to-machine KYC APIs for Brazilian documents:
`document_ocr` (async extraction of CNH/RG fields, `POST /v1/extractions`),
`document_classifier` (sync classification, `POST /v1/classifications`), `biometrics`
(facematch) and `backoffice` (companies, users, service accounts). Shared apps:
`aike_vision` (OpenCV + Tesseract), `aike_storage`, `aike_http`, `aike_auth`,
`aike_observability`, `kyc_core`. Clients are other systems (integration
`app → client backend → Aike`), not end users; there is no UI.

## Usage

- `/po <prompt>` — create a GitHub issue from a feature description
- `/po <prompt> --priority <P0|P1|P2|P3>` — with an explicit priority
- `/po` — ask the user what to build, then create the issue
- `/po amend <issue_number> <summary>` — append a revision to an existing issue

If no `--priority` is given, ask the user which to assign.

## Workflow

1. **Scan the codebase** for current state:
   - The service router, Peri schemas, controllers, JSON views and contexts involved
   - `KycCore.HttpErrors` and `docs/api-errors.md` for the error contract;
     `docs/http-contract.md` for the public contract
   - Engines, extractors and their versions in `config/config.exs`
   - `docs/` for limits and decisions (`capacity.md`, `architecture-target.md`)
   - Identify gaps, dependencies and integration points between apps
2. **Write the PRD** as the issue body (no local file)
3. **Create the GitHub issue** with a conventional title and PRD body

## Issue Title

Conventional format:

```
feat(<scope>): <short description>
```

Scope is the domain or app area. Examples:
- `feat(ocr): extract fields from the new cnh model`
- `feat(classifier): detect the cin identity card`
- `feat(auth): cache service account introspection`
- `feat(storage): store blobs in r2`
- `fix(ocr): reject multi-page pdfs before upload`

Rules: lowercase after prefix, present-tense imperative, under 70 chars.

## Issue Body (PRD)

```markdown
## Overview
What we're building and why.

## Problem Statement
What user problem does this solve?

## Current State
What already exists (endpoint, context, engine, extractor, config, docs).

## Requirements
- [ ] R-1: ...

## Technical Approach
- Affected apps, contexts, schemas and migrations; endpoint, scope and Peri schema
- Error codes to register (`KycCore.HttpErrors`, `AikeHttp.Problem`, `docs/api-errors.md`)
- Engine or extractor versions to bump; config registry entries
- Privacy: which personal data is touched and where it must never appear
- Capacity: CPU per request or job, limits and timeouts (`docs/capacity.md`)
- Docs to update in `docs/`

## Acceptance Criteria
Given/When/Then scenarios.

## Out of Scope
What we're explicitly NOT doing.
```

## Creating the Issue

```bash
gh issue create \
  --title "feat(<scope>): <description>" \
  --body "$(cat <<'EOF'
<PRD content>
EOF
)" \
  --label "prd" \
  --label "P2: medium"
```

Replace the priority label with the chosen one (`P0: critical`, `P1: high`,
`P2: medium`, `P3: low`). If the `prd` label doesn't exist, create it first:

```bash
gh label create prd --description "Product Requirements Document" --color "0075ca"
```

Report the issue URL when done.

## Amending an Issue

`/po amend <issue_number> <summary>` appends a revision. **The original PRD is
immutable** — never edit or overwrite it.

1. **Fetch** the issue: `gh issue view <number> --json title,body`
2. **Read** the summary from the engineer
3. **Research** the codebase to validate the proposed changes
4. **Append** a revision block:

```bash
gh issue edit <number> --body "$(cat <<'EOF'
<original body unchanged>

---

## Revision <N> — <date>

**Source:** implementer research

### Changes
- <what changed and why>

### Updated Requirements
- [ ] R-X: <new or modified requirement>

### Removed/Deferred
- ~~R-Y: <requirement removed or moved to out of scope>~~
EOF
)"
```

### Amend Rules

- **Never modify the original PRD text** — append only
- **Increment the revision number** (Revision 1, 2, ...)
- **Each revision is self-contained** — readable without diffing
- **Link the source** — who requested the change and why
- Push back to the user if the amendment contradicts product goals

## Constraints

- Elixir umbrella, Phoenix JSON APIs, Ecto/Postgres, Oban. Thin controllers, logic in
  contexts, no dependency between processing services
- Personal data (LGPD) never in logs, errors, job args, fixtures or Git
- System tools come from `flake.nix` (Tesseract, Poppler, OpenCV); production needs them
  too
- **No new dependencies** unless clearly justified in the PRD

## Pipeline

```
/po <prompt> → GitHub issue → /dev <issue> → /review → commit → /open-pr
                   ^                |
                   |                | (PRD feedback)
                   +--- /po amend --+
```
