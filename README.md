# Aike

> **Proof of concept. Not for production.**
> Aike is a study project. I built it to learn Elixir while working with LLMs (AI coding
> assistants). It is not a product, and nobody audited it. Do not use it with real personal
> data, and do not rely on it for real identity checks.

Aike is a set of machine-to-machine KYC APIs for Brazilian documents (CNH and RG):
classification, OCR data extraction and face matching. The customer app talks to the
customer backend, and only the backend calls Aike.

| Service | Local port | What it does |
|---|---|---|
| `document_ocr` | 4000 | `POST /v1/extractions`: extracts the document fields (Tesseract + OpenCV) |
| `document_classifier` | 4001 | `POST /v1/classifications`: type, side and quality, synchronously |
| `biometrics` | 4002 | `POST /v1/facematch`: compares a selfie with the document photo (OpenCV) |
| `backoffice` | 4003 | companies, service accounts and credential validation |

The project is a modular monolith in Elixir (an umbrella). Each service has its own
release, image and database, and it can run on its own machine. The detailed documents in
[`docs/`](docs) are in Portuguese.

## What you can learn from it

- A Phoenix JSON API without HTML, with input validation in [Peri](https://hex.pm/packages/peri).
- Async pipelines with Ecto and Oban (preprocess, OCR, extract, validate, complete).
- Umbrella boundaries that a script enforces (`scripts/check_boundaries.exs`).
- OpenCV (`evision`) and Tesseract behind small behaviours with fake engines for tests.
- A single error contract, idempotency keys, webhooks and tenant isolation.

## Run it locally

You need Nix with flakes and Docker (or Podman with the Docker socket). The Nix shell
brings Elixir, Erlang, Tesseract, Poppler, `curl` and `jq`. The first compilation takes a
few minutes.

```bash
nix develop path:.
export MIX_HOME="$PWD/.nix-mix" HEX_HOME="$PWD/.nix-hex"
mix local.hex --force && mix local.rebar --force
mix deps.get

docker compose up -d postgres seaweedfs seaweedfs-init
mix ecto.create && mix ecto.migrate
scripts/fetch_face_models.sh

export AIKE_AUTH_TOKEN="$(openssl rand -hex 32)"
mix phx.server
```

`AIKE_AUTH_TOKEN` is the internal token that the services use to validate credentials in
the backoffice. In production, use the same value in every service.

Check that the four services answer:

```bash
for port in 4000 4001 4002 4003; do
  curl -s -o /dev/null -w "$port %{http_code}\n" "http://localhost:$port/health"
done
```

Each line must show `200`. With direnv, `direnv allow` loads the environment from `.envrc`.

The Compose file starts:

- PostgreSQL 18 on `127.0.0.1:5432` (`PGPORT` changes the port);
- SeaweedFS as S3 on `127.0.0.1:8333`, with the bucket `aike-dev`;
- the file browser at `http://127.0.0.1:8888/buckets/aike-dev/`.

To stop, end `mix phx.server` and run `docker compose stop`.

## First calls

Create a company and a service account. The secret appears only once:

```bash
cd apps/backoffice
mix aike.company.create Konoha
mix aike.service_account.create <COMPANY_UUID> "Konoha Development" \
  ocr:write,ocr:read,classifier:write,facematch:write,facematch:read
cd ../..
```

Extract the data of a document and wait up to 10 seconds for the result:

```bash
curl -sS http://localhost:4000/v1/extractions \
  -H "authorization: ApiKey <accountId>:<secret>" \
  -H "prefer: wait=10" \
  -F "file=@cnh.pdf" | jq
```

Only the file is required: the type is detected and the default country is `BR`. Without
`prefer`, the answer is `202` at once, and the result arrives by webhook or by
`GET /v1/extractions/:id`. Every response uses the same envelope (`id`, `version`,
`data`, `metadata`). See the [HTTP contract](docs/http-contract.md) and the
[errors](docs/api-errors.md).

Classify the same file. The answer has type, country, side, confidence and quality:

```bash
curl -sS http://localhost:4001/v1/classifications \
  -H "authorization: ApiKey <accountId>:<secret>" \
  -F "file=@cnh.pdf" | jq
```

Compare a selfie with the document photo. Without `prefer: wait=N`, the answer is `202`
with a `location` header. Read the result at `GET /v1/facematch/:id`:

```bash
curl -sS http://localhost:4002/v1/facematch \
  -H "authorization: ApiKey <accountId>:<secret>" \
  -F "selfieImage=@selfie.jpg" \
  -F "documentImage=@cnh.jpg" | jq
```

Use test files that you made yourself. Never use documents of other people.

The smoke scripts test the flows end to end. They need `AIKE_ACCOUNT_ID` and
`AIKE_ACCOUNT_SECRET`:

- `scripts/smoke-classifier.sh` needs `CLASSIFIER_FILE` with an image or PDF of yours.
- `scripts/smoke.sh` and `scripts/smoke-reprocess.sh` send a fake image. They complete only
  with the `DocumentOcr.OCR.Fake` engine. With the default Tesseract engine, the document
  stays in `processing`.

## Tests and quality

```bash
MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
mix run --no-start scripts/check_boundaries.exs
```

`check_boundaries.exs` makes sure that one service does not depend on another. The rules
for code and tests are in [`.claude/rules/`](.claude/rules).

## Documentation

The documents are in Portuguese.

| Subject | Document |
|---|---|
| Boundaries, databases and webhook | [architecture-target.md](docs/architecture-target.md) |
| Deployment, images and variables | [deploy.md](docs/deploy.md) |
| HTTP contract | [http-contract.md](docs/http-contract.md), [api-errors.md](docs/api-errors.md) |
| OCR engines and versions | [ocr-engines.md](docs/ocr-engines.md), [classifier-tesseract.md](docs/classifier-tesseract.md) |
| Capacity and peaks | [capacity.md](docs/capacity.md) |
| Storage and metrics | [local-storage-and-metrics.md](docs/local-storage-and-metrics.md) |
| Facematch: engine, decision and limits | [facematch.md](docs/facematch.md) |
| Backoffice | [backoffice.md](docs/backoffice.md) |
| Idempotency, reconciliation, reprocessing | [idempotency-and-recovery.md](docs/idempotency-and-recovery.md), [reconciliation.md](docs/reconciliation.md), [reprocessing.md](docs/reprocessing.md) |

## Privacy

Never put real documents or personal data in Git, in logs or in fixtures. The tests build
synthetic documents with fictional names.

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before you open a pull request. To report a
vulnerability, follow [SECURITY.md](SECURITY.md). Do not open a public issue for it.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
