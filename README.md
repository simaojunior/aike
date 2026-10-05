# Aike — KYC pipelines fake

Umbrella Elixir da Aike com `document_ocr` (Phoenix, Ecto, Oban),
`document_classifier`, `biometrics`, `aike_storage` e `kyc_core` (vocabulário puro).
Storage, OCR, classificação e biometria usam engines fake injetáveis. Nenhum modelo
ML foi adicionado.

## Ambiente NixOS

O flake fixa o ambiente com seu lock: OTP 28, Elixir via overlay,
cliente PostgreSQL 18 e Docker Compose. O servidor PostgreSQL roda em container.

```bash
cd aike
nix develop path:.
export MIX_HOME="$PWD/.nix-mix"
export HEX_HOME="$PWD/.nix-hex"
mix local.hex --force
mix local.rebar --force
mix deps.get
docker compose up -d postgres
mix ecto.create
mix ecto.migrate
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix phx.routes DocumentOcrWeb.Router
mix phx.routes DocumentClassifierWeb.Router
mix phx.server
```

Com direnv, `direnv allow` carrega `.envrc` e configura os diretórios locais do Mix/Hex.
Se este diretório for adicionado a um repositório Git, inclua os arquivos do flake no Git
para que `use flake` consiga vê-los. `nix develop path:.` também funciona sem Git.

Na máquina de referência, `docker` usa Podman. Se o Compose não detectar o socket:
`export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"`.
`PGPORT` altera a porta do Compose e do Repo; padrão 5432. `PORT` altera a API OCR;
padrão 4000. `CLASSIFIER_PORT` altera o classifier; padrão 4001.
Na raiz, `mix phx.server` inicia ambas as APIs.
Pare o banco com `docker compose down` (sem `-v`, preservando dados).

PostgreSQL 18 usa `postgres18_data:/var/lib/postgresql`. O volume `kyc_postgres_data`
inicializado brevemente com PostgreSQL 17 foi preservado e não é utilizado pelo 18.

## API e teste manual

### Provisionar credenciais locais

Empresas e Service Accounts são criadas fora dos endpoints públicos. O segredo da
Service Account é gerado somente durante o provisionamento e não pode ser recuperado
depois:

```bash
mix ecto.migrate -r DocumentOcr.Repo
mix aike.company.create acme Acme
mix aike.service_account.create \
  acme "Acme Development" \
  ocr:write,ocr:read,biometrics:write,biometrics:read
```

O segundo comando imprime o `account_id` e o `secret`. Guarde o segredo e use-o nas
requisições autenticadas:

```text
Authorization: ApiKey <account_id>:<secret>
```

O segredo nunca é salvo em texto puro. A tabela armazena apenas um hash PBKDF2, e os
escopos permitidos são `ocr:write`, `ocr:read`, `biometrics:write` e
`biometrics:read`. Não existem escopos de update ou delete.

Em outro terminal, com a API em execução:

```bash
bash scripts/smoke.sh
```

O script requer curl e jq, cria um documento fake e verifica HTTP, execução assíncrona
dos cinco jobs e resultado persistido. Deixa o documento de demonstração no banco local.

Endpoints:

- `POST /v1/documents`: corpo conforme o guia, retorna 202 com ID/status.
- `GET /v1/documents/:id`: estado, tipo/country e `result` quando disponível.
- `POST /v1/documents/:id/reprocess`: recebe pipeline_version ativo e retorna 202
  com nova execução. Criação, consultas e reprocessamento expõem `run_id`.
- O mesmo `GET /v1/documents/:id` retorna `result: null` durante o processamento e o
  resultado persistido quando o documento chega a um estado terminal.
- Requests inválidos retornam 422. Nesta etapa apenas CNH/BR é aceita, com lados
  front/back/single e source.type object_storage. RG ainda não possui extractor.

CPF de sucesso: `529.982.247-25`. O CPF `123.456.789-00` do guia é inválido e deve
ser rejeitado pelo checksum. Os dados de OCR são fixtures, não resultados de ML.

## Persistência e execução

Migrations `20261004000001_add_oban` e `20261004000002_create_documents` criam
Oban, documentos, imagens, artefatos e resultados; IDs de domínio são UUIDs.
Criação do documento/imagens/job é atômica. Cada etapa usa lock por documento,
upsert de artefatos/resultados e enfileiramento transacional. Jobs possuem até três
tentativas; falhas transitórias mantêm processing, esgotamento marca failed.
Transições consultam o estado atual sob lock, protegendo estados terminais contra
structs antigos. Jobs de documentos removidos são cancelados sem novos jobs.
CPF/data inválidos resultam em rejected; confiança abaixo de 0.90 pede confirmação.
Esses limiares são provisórios.

Para simplificar este fake, bytes pré-processados são base64 em um artefato JSONB;
Storage e OCR rodam fora da transação que mantém o lock; persistência do artefato
e próximo job usam transações curtas protegidas por run_id. Antes de engines reais,
mover artefatos binários para storage privado e definir timeout cooperativo.
O extractor fake usa os três primeiros itens da imagem front, com fallback single
e back; não implementa fusão de frente/verso ou layouts RG. Normalização do CPF
remove apenas pontuação/espaços, preservando letras inválidas para rejeição.
RG é rejeitado tanto na API quanto no contexto de criação de documentos.
Reprocessamento está disponível com um único resultado atual, sem histórico.
Ele substitui os artefatos/resultados anteriores numa transação e impede que jobs
antigos modifiquem a nova execução. A migration `20261005000002_add_processing_runs`
adiciona identidade de execução e FKs compostas. Veja
[docs/reprocessing.md](docs/reprocessing.md) para política de versões, concorrência
e atualização de jobs legados; teste manual: `bash scripts/smoke-reprocess.sh`.

Configuração: `storage`, `ocr_engine`, `pipeline_version`, `ocr_engine_version`,
`extractor_version`, com registros `ocr_engines` e `extractors`. A configuração é
capturada no documento na criação; workers, logs e resultados usam essas versões
mesmo que os defaults mudem. A migration `20261005000001_pin_processing_configuration`
adiciona os campos de proveniência no documento. Resultados legados são preservados;
documentos antigos sem configuração registrada não recebem versões presumidas e
falham após retries se ainda estiverem pendentes. Consulte
[docs/ocr-engines.md](docs/ocr-engines.md) para trocar adapters e atualizar o banco.
Logs SQL e parâmetros HTTP
estão desabilitados/filtrados; erros de adapters são reduzidos a códigos sem payload.

Produção exige `SERVICE_TOKEN`, `DATABASE_URL` e `SECRET_KEY_BASE`; autenticação
Bearer é validada na borda. `PHX_SERVER=true` habilita endpoint em releases.
HTTPS, storage privado real, retenção e auditoria ainda dependem da infraestrutura
de produção; este checkpoint é para desenvolvimento local com fakes.

## Classifier independente

O classifier depende somente de Phoenix/Bandit/Jason e `kyc_core`, sem dependência
do OCR, Ecto, Oban ou banco de dados. Não cria documentos nem aciona o pipeline OCR.
O backend principal/mobile decide como agir sobre a resposta.

Para iniciar somente o classifier em desenvolvimento, entre no flake na raiz,
configure Mix/Hex conforme acima e execute:

```bash
cd apps/document_classifier
mix phx.server
```

Para testar somente essa aplicação, `mix test` no mesmo diretório não precisa do
PostgreSQL. Os testes completos na raiz continuam exigindo o banco para OCR.

Em outro terminal, na raiz do projeto:

```bash
bash scripts/smoke-classifier.sh
curl -X POST http://localhost:4001/v1/classifications \
  -H 'content-type: application/json' \
  -d '{"source":{"type":"object_storage","key":"kyc/session-123/frame-001.jpg"}}'
```

`POST /v1/classifications` recebe somente `source.type=object_storage` e uma chave
string não vazia de até 1024 bytes. Retorna `200` com `document` (type/country/side),
`quality` (acceptable/score/issues) e `confidence`. Unknown e qualidade ruim também
retornam `200`; não são falhas técnicas. Requests inválidos retornam `422`, falhas
de storage/engine ou resultado de engine inválido retornam `503` com erro genérico.

Fixtures selecionadas pelo storage fake (nenhum arquivo real é lido):

| Chave | Tipo / lado | Qualidade | Confiança |
| --- | --- | --- | --- |
| `fake/cnh-front.jpg` ou qualquer chave não reservada | cnh / front | 0.96, aceitável | 0.99 |
| `fake/cnh-back.jpg` | cnh / back | 0.96, aceitável | 0.99 |
| `fake/rg-front.jpg` | rg / front | 0.96, aceitável | 0.99 |
| `fake/rg-back.jpg` | rg / back | 0.96, aceitável | 0.99 |
| `fake/rg-single.jpg` | rg / single | 0.96, aceitável | 0.99 |
| `fake/unknown.jpg` | unknown / unknown | 0.91, aceitável | 0.37 |
| `fake/bad-quality.jpg` | cnh / front | 0.42, não aceitável, blur/glare | 0.98 |

Os adapters são configurados em `:document_classifier` pelas chaves `:storage` e
`:engine`. O engine recebe bytes, não chaves de storage. O contrato usa o vocabulário
de `kyc_core` e valida scores entre 0 e 1, sem confundir confiança com qualidade.
Fixtures não são detecção de imagens e não representam acurácia do serviço.

Produção exige Bearer token: `CLASSIFIER_SERVICE_TOKEN` (fallback `SERVICE_TOKEN`).
`CLASSIFIER_SECRET_KEY_BASE` tem fallback `SECRET_KEY_BASE`. A release do classifier
configura somente seu serviço, sem exigir variáveis ou carregar aplicações do OCR.

## Releases independentes

No ambiente Nix, a partir da raiz:

```bash
MIX_ENV=prod mix release document_classifier
MIX_ENV=prod mix release document_ocr
```

Cada release inclui somente seu serviço e dependências. Seu launcher define
`RELEASE_NAME`, usado pelo runtime para selecionar as configurações. Não é necessário
definir essa variável manualmente. Um nome desconhecido falha na inicialização.
Execução via Mix sem release continua configurando o umbrella completo.

Para executar o classifier, configure `CLASSIFIER_SERVICE_TOKEN` e
`CLASSIFIER_SECRET_KEY_BASE` (segredo de pelo menos 64 bytes), então:

```bash
PHX_SERVER=true _build/prod/rel/document_classifier/bin/document_classifier start
```

Para executar OCR, configure `SERVICE_TOKEN`, `SECRET_KEY_BASE` e `DATABASE_URL`
apontando para um banco com as migrations já aplicadas, então:

```bash
PHX_SERVER=true _build/prod/rel/document_ocr/bin/document_ocr start
```

Para executar biometria, configure `BIOMETRICS_SERVICE_TOKEN`,
`BIOMETRICS_SECRET_KEY_BASE` e `DATABASE_URL`:

```bash
PHX_SERVER=true _build/prod/rel/biometrics/bin/biometrics start
```

Os endpoints continuam em loopback, portas 4000/4001/4002. Em produção, requests precisam
do header `Authorization: Bearer <token>`. Tokens ausentes/vazios na configuração
de produção impedem inicialização; o Plug também nega acesso sem token configurado
quando `auth_required` está ativo. Os scripts smoke HTTP são para desenvolvimento
sem autenticação, não para esses endpoints de produção.

Com as mesmas variáveis de cada release, esta verificação local inicia o serviço
sem servidor HTTP, verifica isolamento e autenticação pela fronteira Plug, e faz
`SELECT 1` no caso do OCR. Não grava dados:

```bash
_build/prod/rel/document_classifier/bin/document_classifier eval 'Code.require_file("scripts/check_release.exs")'
_build/prod/rel/document_ocr/bin/document_ocr eval 'Code.require_file("scripts/check_release.exs")'
```

As releases geradas em NixOS usam o ambiente/runtime Nix disponível nesta máquina;
isso não equivale a uma imagem portável ou implantação em outro sistema.

A revisão e suas limitações estão em [docs/architecture-review.md](docs/architecture-review.md).

## Qualidade estática

O projeto inclui Credo para análise de estilo e padrões Elixir e Dialyzer para
análise de tipos por success typing. O gate combinado roda dentro do ambiente Nix:

```bash
nix develop --command mix quality
```

Também é possível executar cada ferramenta separadamente:

```bash
nix develop --command mix credo --strict
nix develop --command mix dialyzer
```

O Credo reporta oportunidades de refatoração e documentação existentes no código;
o Dialyzer deve terminar sem erros. Avisos específicos de opacidade gerados pelas
estruturas internas do Ecto são documentados em `dialyzer.ignore-warnings` ou nos
atributos `@dialyzer` dos módulos afetados.

Os payloads de entrada possuem schemas Peri nos módulos `*_web/schemas` e são
validados no boundary HTTP antes dos contextos. O Elixir 1.20 também oferece tipos
graduais set-theoretic; o projeto continua usando `@spec` e Dialyzer como contrato
estável enquanto essa tipagem é adotada gradualmente no domínio.

A observabilidade segue o padrão do Kuatia: logging estruturado por evento,
correlation ID via `x-request-id`, duração em milissegundos e níveis derivados do
status HTTP. O helper compartilhado em `KycCore.Observability` redige dados
sensíveis recursivamente.

## Próximo checkpoint

O próximo passo é conectar um adapter R2 compatível com S3 e adicionar métricas
externas de filas. A base de retenção, duração de etapas e política de idempotency
key já está preparada. Modelos reais continuam fora do escopo.
