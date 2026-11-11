# Aike

APIs de KYC para documentos brasileiros (CNH e RG): classificação, extração de dados por
OCR e facematch. São serviços máquina a máquina: o app do cliente fala com o backend do
cliente, e só o backend chama o Aike.

| Serviço | Porta local | O que faz |
|---|---|---|
| `document_ocr` | 4000 | `POST /v1/extractions`: extrai os campos do documento (Tesseract + OpenCV) |
| `document_classifier` | 4001 | `POST /v1/classifications`: tipo, lado e qualidade, de forma síncrona |
| `biometrics` | 4002 | `POST /v1/facematch`: compara a selfie com a foto do documento (OpenCV) |
| `backoffice` | 4003 | empresas, service accounts e validação das credenciais |

O projeto é um monolito modular em Elixir (umbrella). Cada serviço tem release, imagem e
banco próprios, e pode rodar numa máquina separada. Veja
[Arquitetura](docs/architecture-target.md) e [Implantação](docs/deploy.md).

## Rodar localmente

Requisitos: Nix com flakes e Docker (ou Podman com o socket do Docker).

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

Com direnv, `direnv allow` carrega o ambiente do `.envrc`.

O flake traz Elixir, Erlang, o cliente do PostgreSQL, Tesseract, Poppler e Python com
OpenCV (só para os scripts de referência). O Compose sobe:

- o PostgreSQL 18 em `127.0.0.1:5432` (`PGPORT` muda a porta);
- o SeaweedFS como S3 em `127.0.0.1:8333`, com o bucket `aike-dev`;
- a interface dos arquivos em `http://127.0.0.1:8888/buckets/aike-dev/`.

## Primeira chamada

Crie uma empresa e uma service account (o segredo aparece uma vez):

```bash
cd apps/backoffice
mix aike.company.create Konoha
mix aike.service_account.create <COMPANY_UUID> "Konoha Development" \
  ocr:write,ocr:read,classifier:write,facematch:write,facematch:read
cd ../..
```

Extraia os dados de um documento e espere o resultado por até 10 segundos:

```bash
curl -sS http://localhost:4000/v1/extractions \
  -H "authorization: ApiKey <accountId>:<secret>" \
  -H "prefer: wait=10" \
  -F "file=@cnh.pdf" | jq
```

Só o arquivo é obrigatório: o tipo é detectado e o país padrão é `BR`. Sem `prefer`, a
resposta é `202` na hora; o resultado chega por webhook ou por
`GET /v1/extractions/:id`. Todas as respostas usam o mesmo envelope
(`id`, `version`, `data`, `metadata`). Veja o [Contrato HTTP](docs/http-contract.md) e os
[Erros](docs/api-errors.md).

`scripts/smoke.sh`, `scripts/smoke-classifier.sh` e `scripts/smoke-reprocess.sh` testam
os fluxos de ponta a ponta. Eles pedem `AIKE_ACCOUNT_ID` e `AIKE_ACCOUNT_SECRET`.

## Testes e qualidade

```bash
MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
mix run --no-start scripts/check_boundaries.exs
```

`check_boundaries.exs` garante que um serviço não depende de outro. As regras do projeto
para código e testes estão em `.claude/rules/`.

## Documentação

| Assunto | Documento |
|---|---|
| Fronteiras, bancos e webhook | [architecture-target.md](docs/architecture-target.md) |
| Implantação, imagens e variáveis | [deploy.md](docs/deploy.md) |
| Contrato HTTP | [http-contract.md](docs/http-contract.md), [api-errors.md](docs/api-errors.md) |
| Motores de OCR e versões | [ocr-engines.md](docs/ocr-engines.md), [classifier-tesseract.md](docs/classifier-tesseract.md) |
| Capacidade e picos | [capacity.md](docs/capacity.md) |
| Storage e métricas | [local-storage-and-metrics.md](docs/local-storage-and-metrics.md) |
| Facematch: motor, decisão e limites | [facematch.md](docs/facematch.md) |
| Backoffice | [backoffice.md](docs/backoffice.md) |
| Idempotência, reconciliação, reprocessamento | [idempotency-and-recovery.md](docs/idempotency-and-recovery.md), [reconciliation.md](docs/reconciliation.md), [reprocessing.md](docs/reprocessing.md) |

## Privacidade

Nunca coloque documentos reais ou dados pessoais no Git, em logs ou em fixtures. Os
testes geram documentos sintéticos com nomes fictícios.

## Licença

Apache License 2.0. Veja [LICENSE](LICENSE) e [NOTICE](NOTICE).
