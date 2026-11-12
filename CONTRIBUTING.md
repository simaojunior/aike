# Contributing

Thank you for your interest. Aike is a study project (a proof of concept), so the
process is light. This guide shows the minimum flow to propose a change.

## Before you start

1. Follow the steps in the [README](README.md) to prepare your environment.
2. Open an issue before you write code for a large change.
3. Read the project rules in [`.claude/rules/`](.claude/rules): `elixir.md`, `testing.md`
   and `git.md`.

## Main rules

- Write the test first. The test defines the correct behavior.
- A service never depends on another service and never reads its tables.
- Validate every client input with a Peri schema in `*Web.Schemas.*Params`. Accept only
  camelCase field names.
- Every new error needs its atom in `KycCore.HttpErrors`, its code in `AikeHttp.Problem`,
  its entry in `docs/api-errors.md` and a test that checks the `code`.
- Do not write code comments. Put the reason in the `@moduledoc` or in `docs/`.
- Never send real documents, personal data or secrets. The tests use synthetic data with
  Naruto-universe names and the test CPF `529.982.247-25`.

## Checks before a commit

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
mix run --no-start scripts/check_boundaries.exs
```

## Commits and pull requests

- Use conventional commits: `<type>(<scope>): <short description>`.
  Types: `feat`, `fix`, `refactor`, `test`, `chore`, `docs`, `perf`.
- Make one commit for each concern. Put the documentation of a change in the same commit.
- In the pull request, say what changed, why it changed and how you tested it.

## License

When you contribute, you agree that your contribution uses the
[Apache License 2.0](LICENSE).
