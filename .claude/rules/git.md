---
description: Git operations — committing, branching, staging
globs: ["**/*"]
alwaysApply: false
---

# Git Conventions

## Commits

Format: `<type>(<scope>): <short description>`.

Types: `feat`, `fix`, `refactor`, `test`, `chore`, `docs`, `perf`.

Scopes follow the app or area: `ocr`, `classifier`, `biometrics`, `backoffice`, `auth`,
`api`, `vision`, `storage`, `config`, `nix`.

Rules:
- Present tense ("add", not "added"), lowercase after the prefix, brief
- Never mention AI or Claude; no Co-Authored-By trailers; no emojis

## Atomic commits

- One concern per commit. A migration, its schema and the context code that uses it may
  share a commit; an unrelated refactor may not
- Docs that describe a change go with that change

## Staging

- `git add <specific files>`; never `git add .` or `git add -A`
- Review `git diff --staged` before committing
- Never stage personal documents, `.env` files, uploads (`var/uploads/`) or test outputs

## Branches

`feat/<name>`, `fix/<name>`, `refactor/<name>`, `chore/<name>`.

## Pre-commit gate

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
mix run --no-start scripts/check_boundaries.exs
```

## Examples

```bash
git add apps/document_ocr/lib/document_ocr/extraction/rg_labels.ex \
        apps/document_ocr/test/rg_labels_test.exs
git commit -m "feat(ocr): extract rg fields by label"

git add apps/kyc_core/lib/kyc_core/http_errors.ex \
        apps/document_classifier/lib/document_classifier_web/fallback_controller.ex
git commit -m "fix(classifier): answer overload with retry-after"
```
