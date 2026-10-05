# Contrato HTTP

## Autenticação

Em desenvolvimento os endpoints podem operar sem autenticação. Em produção, cada
serviço exige credenciais M2M:

```text
Authorization: ApiKey <service-account-id>:<secret>
```

O token é configurado por ambiente (`SERVICE_TOKEN`, `CLASSIFIER_SERVICE_TOKEN` ou
`BIOMETRICS_SERVICE_TOKEN`) e validado no boundary Phoenix. Falhas retornam `401`.

Os routers usam escopos explícitos por pipeline:

```text
ocr:write          POST /v1/documents e ações de processamento
ocr:read           GET  /v1/documents/:id (inclui `result` quando disponível)
classifier:write   POST /v1/classifications
classifier:read    reservado para consultas futuras do classifier
facematch:write    POST /v1/facematch
facematch:read     GET  /v1/facematch/:id
biometrics:write   alias de compatibilidade para `facematch:write`
biometrics:read    alias de compatibilidade para `facematch:read`
```

O endpoint síncrono do classifier usa `classifier:write`. Não existem escopos de
update ou delete. `company_id` é sempre derivado da conta autenticada.

## Provisionamento temporário

Durante o desenvolvimento, estes endpoints administrativos permanecem sem
autenticação para permitir o bootstrap inicial:

```http
POST /v1/companies
Content-Type: application/json

{"name":"Acme"}
```

A resposta `201` contém um `id` UUID. Use esse UUID para criar uma Service Account:

```http
POST /v1/service-accounts
Content-Type: application/json

{"companyId":"<company-uuid>","name":"Acme Development","scopes":["ocr:write","ocr:read"]}
```

A resposta `201` contém o `accountId` e o `secret` em texto puro uma única vez. O
segredo não é persistido; somente seu hash é armazenado. Esses endpoints devem
receber autenticação administrativa antes de qualquer ambiente compartilhado ou
produção.

As colunas e estruturas internas usam `snake_case`. Todas as respostas JSON passam
por conversão recursiva para `camelCase` (`runId`, `documentType`, `processingTimeMs`).

## Criação de documentos

`POST /v1/documents` aceita os dois formatos.

JSON:

```json
{
  "app_id": "acme",
  "external_id": "user-9876",
  "document": {"type": "cnh", "country": "BR"},
  "images": [
    {"side": "front", "source": {"type": "object_storage", "key": "capture/front.jpg"}}
  ]
}
```

Multipart:

```text
app_id=acme
external_id=user-9876
document_type=cnh
country=BR
image_front=<arquivo>
image_back=<arquivo opcional>
```

O JSON mantém compatibilidade com fontes que já possuem uma chave de objeto. O
multipart faz o upload dos bytes para o storage interno e cria o `Blob` correspondente.
Ambos retornam `202` com `id`, `runId` e `status`.

O estado técnico (`status`) é separado da decisão de negócio (`decision`). Um
documento concluído pode ter `approved`, `rejected` ou `manualReview`.

## Idempotência

Clientes que repetem uma criação devem enviar `Idempotency-Key`. A chave é limitada
a 256 caracteres e é única por `company_id`/aplicação. Uma repetição com a mesma
chave devolve o documento original sem criar novo job; chaves diferentes criam
execuções independentes. A chave não deve ser reutilizada para outro payload.

## Retenção

Blobs são armazenados pelo adapter privado configurado pelo serviço. A rotina de
retenção remove primeiro o objeto do storage e depois o registro `blobs`, respeitando
as referências existentes. O período padrão é configurável por
`config :aike_storage, :retention_seconds`.

## Observabilidade

Os serviços seguem o padrão de logging estruturado do Kuatia. Cada requisição
recebe ou propaga `x-request-id` e emite `http.request.completed` ao finalizar,
com serviço, método, status, classe do status e `duration_ms`. Respostas 2xx são
registradas em `info`, 4xx em `warning` e 5xx em `error`.

Campos sensíveis como CPF, nome, data de nascimento, OCR bruto, tokens, segredos e
bytes de imagem são redigidos antes de qualquer log. O `company_id`, `service_account_id`,
`document_id` e `run_id` podem ser usados para correlação operacional.

## Cancelamento

```text
POST /v1/documents/:id/cancel
```

Documentos `pending` ou `processing` passam para `failed` com `error_code: "cancelled"`.
Jobs antigos retornam cancelamento quando executados. Um documento terminal não pode
ser cancelado novamente e retorna `409`.
