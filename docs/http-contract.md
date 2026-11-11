# Contrato HTTP

## Convenções

- **Campos em camelCase, na entrada e na saída.** JSON, form-data e query string usam os
  mesmos nomes das respostas: `appId`, `externalId`, `documentType`, `imageFront`,
  `imageBack`, `selfieImage`, `documentImage`, `pipelineVersion`. Um campo enviado em
  snake_case (`selfie_image`) é ignorado, e a falta do campo certo responde `422
  validation` com o nome em camelCase.
- **Headers em minúsculas:** `authorization`, `prefer`, `idempotency-key`, `location`,
  `preference-applied`, `retry-after`. O HTTP não diferencia maiúsculas nos nomes de
  header, então `Prefer` também funciona; a documentação e as respostas usam minúsculas.

## Autenticação

Os endpoints de processamento exigem autenticação por service account, inclusive
em desenvolvimento:

```text
authorization: ApiKey <service-account-id>:<secret>
```

O identificador e o segredo são emitidos no provisionamento da service account e
validados no boundary Phoenix. Credenciais ausentes ou inválidas retornam `401`;
escopo insuficiente retorna `403`.

Os routers usam escopos explícitos por pipeline:

```text
ocr:write          POST /v1/extractions e ações de processamento
ocr:read           GET  /v1/extractions/:id (inclui `result` quando disponível)
classifier:write   POST /v1/classifications
classifier:read    reservado para consultas futuras do classifier
facematch:write    POST /v1/facematch
facematch:read     GET  /v1/facematch/:id
biometrics:write   alias de compatibilidade para `facematch:write`
biometrics:read    alias de compatibilidade para `facematch:read`
```

O endpoint síncrono do classifier usa `classifier:write`. Não existem escopos de
update ou delete. `company_id` é sempre derivado da conta autenticada.

## Provisionamento no backoffice

Os endpoints administrativos pertencem ao backoffice em `http://localhost:4003`.
Exigem `authorization: Bearer <accessToken>` de uma sessão humana em todos os ambientes.
O token de bootstrap só cria o primeiro administrador em `POST /v1/auth/bootstrap`;
o login em `POST /v1/auth/login` emite o par access/refresh.
Veja [papéis, sessões, rotas e erros do backoffice](backoffice.md).
Não dependem da API OCR e não estão mais disponíveis na porta 4000:

```http
POST /v1/companies
authorization: Bearer <accessToken>
content-type: application/json

{"name":"Konoha"}
```

A resposta `201` contém um `id` UUID. Use esse UUID para criar uma Service Account:

```http
POST /v1/service-accounts
authorization: Bearer <accessToken>
content-type: application/json

{"companyId":"<company-uuid>","name":"Konoha Development","scopes":["ocr:write","ocr:read"]}
```

A resposta `201` contém o `accountId` e o `secret` em texto puro uma única vez. O
segredo não é persistido; somente seu hash é armazenado. Service accounts de clientes
não autorizam operações administrativas. O provisionamento local continua disponível por CLI
no diretório `apps/backoffice`, sem iniciar qualquer serviço de processamento.

As colunas e estruturas internas usam `snake_case`. Todas as respostas JSON passam
por conversão recursiva para `camelCase` (`runId`, `documentType`, `processingTimeMs`).

## Classificação de documentos

`POST /v1/classifications` exige o escopo `classifier:write` e recebe os bytes
diretamente, sem referências a objetos no storage:

- JSON: `{"image":"<base64 dos bytes do documento>"}`.
- Multipart: arquivo no campo `file` ou `image`.

JSON retorna `document`, `quality` e `confidence`. Multipart retorna o envelope
ordenado `id`, `version`, `data`, `metadata`; cada item de `data` contém
`classification`, `quality` e `fileInfo`. A ordem é de apresentação e não altera
a semântica de objetos JSON.

O contrato antigo com `source.type=object_storage` retorna `422`, assim como
base64 inválido ou conteúdo vazio. Falhas do engine retornam `503` sem detalhes
internos. Com o nó sobrecarregado, a resposta é `503` com o cabeçalho `retry-after`
(segundos): repita depois desse tempo, com backoff e jitter. Ver `docs/capacity.md`.

Classificações não são persistidas. Cada chamada executa o engine, inclusive
reenvios do mesmo conteúdo ou chamadas simultâneas. O status de sucesso continua
`200`; o envelope multipart inclui os metadados do arquivo enviado na chamada.
A identidade vem da introspecção interna no backoffice; falha de comunicação com
a identidade retorna `503`, credenciais inválidas `401` e scope insuficiente `403`.

## Facematch

`POST /v1/facematch` recebe multipart com `selfieImage` e `documentImage`, e
`externalId` opcional (a sua referência; sem ele, o serviço gera um UUID). Cada arquivo pode ser JPEG, PNG ou PDF de uma página (a CNH digital
entra direto). Como na extração, o modelo é híbrido:

- com `prefer: wait=N` (máximo 10 s), a resposta é `200` com o resultado quando a
  comparação termina a tempo, e traz `preference-applied: wait=N`;
- sem o header, ou quando o prazo acaba, a resposta é `202` com
  `location: /v1/facematch/:id`.

`GET /v1/facematch/:id` devolve o estado atual e só encontra sessões da própria empresa;
a sessão de outra empresa responde `404`. Todas as respostas usam o envelope padrão:

```json
{
  "id": "<uuid>",
  "version": "v1",
  "status": "completed",
  "error": null,
  "data": [
    {
      "faceMatch": {"matched": true, "similarity": 0.71, "decision": "approved"},
      "resources": [
        {"fieldname": "selfieImage", "page": 0,
         "face": {"confidence": 0.95, "boundingBox": {"top": 0.21, "left": 0.33, "width": 0.3, "height": 0.41}}},
        {"fieldname": "documentImage", "page": 0,
         "face": {"confidence": 0.94, "boundingBox": {"top": 0.46, "left": 0.25, "width": 0.14, "height": 0.24}}}
      ]
    }
  ],
  "metadata": {
    "filesInfo": [
      {"fieldname": "selfieImage", "mimetype": "image/jpeg", "size": 48213, "sha256": "<hex>", "faces": 1, "issues": []},
      {"fieldname": "documentImage", "mimetype": "application/pdf", "size": 110464, "sha256": "<hex>", "faces": 1, "issues": []}
    ],
    "processingTimeMs": 742,
    "createdAt": "2026-10-15T12:00:00.000000Z",
    "updatedAt": "2026-10-15T12:00:00.742000Z"
  }
}
```

- `status`: `pending`, `processing`, `completed` ou `failed`.
- `decision`: `approved`, `manual_review` ou `rejected`; `similarity` vai de 0 a 1, com
  duas casas. As faixas estão em [Facematch](facematch.md).
- `resources`: o rosto usado em cada arquivo; `boundingBox` em proporções da imagem. O
  recorte do rosto não é devolvido.
- Sem rosto utilizável em algum arquivo, não há comparação: `status` é `completed`,
  `data` é `[]` e `filesInfo[].issues` diz o motivo (`no_face`, `multiple_faces`,
  `face_too_small`).
- Com `failed`, `error` traz `{"code": "processing_failed", "message": "..."}`.
- O facematch não faz prova de vida.

## Reutilização no facematch

OCR e facematch também reutilizam recursos ainda em andamento com `202`, sem
outro job. Ambos aceitam `idempotency-key`: mesma chave com outro payload retorna
`409 {"code":"idempotency_conflict","detail":"This idempotency key is already bound to a different request."}`. A repetição retorna o estado atual do
recurso vinculado, inclusive falha terminal com `200`; isso não gera novo processamento.
Veja [Idempotência e recuperação](idempotency-and-recovery.md).

`POST /v1/facematch` retorna `200` com a sessão e o resultado existentes quando
encontra uma comparação concluída para a mesma empresa, blob da selfie, blob do
documento, engine e `engine_version`. Os blobs são identificados por SHA-256;
selfie e documento têm papéis distintos na chave. Alterar qualquer uma das imagens
gera nova sessão com `202` e novo processamento. Falhas técnicas e sessões ainda
pendentes não são reutilizadas como resultado concluído.

O tenant vem da service account autenticada; o `appId` do payload não o substitui.
Resultados antigos sem versão registrada não são reutilizados. Ao atualizar o
modelo ou parâmetros que alteram seu resultado, incremente `engine_version` na
configuração de `:document_classifier` ou `:biometrics`. Uma comparação já
enfileirada não roda silenciosamente com uma versão diferente da registrada.

## Criação de documentos

`POST /v1/extractions` aceita os dois formatos. Só o documento é obrigatório:

```bash
curl -X POST "$BASE_URL_OCR/v1/extractions" \
  -H "authorization: Bearer $TOKEN" \
  -F "file=@documento.jpg"
```

- `file`: o documento inteiro numa imagem ou num PDF de uma página. Use `imageFront` e
  `imageBack` para enviar os lados em arquivos separados.
- `documentType`: `cnh` (ou `drivers_license`) ou `rg` (ou `id_card`). Sem ele, o tipo é
  `auto` e o pipeline o detecta pelo texto. A resposta mostra o tipo detectado. Sem tipo
  reconhecível, o documento termina como `failed` com `error_code=unrecognized_document`.
- `country`: só `BR` (ou `BRA`), o padrão.
- `externalId`: a sua referência. Sem ele, o serviço gera um UUID.

No RG, os dados ficam no verso.

### Espera pelo resultado (`prefer: wait`)

O `POST /v1/extractions` aceita o cabeçalho `prefer: wait=N` (RFC 7240), com N em segundos
e teto de 10 (`max_wait_seconds`). Se a extração terminar dentro da espera, a resposta é
`200` com o recurso pronto. Se não, `202` com `location`, e a extração segue na fila. Nos
dois casos a resposta traz `preference-applied: wait=N`. Sem o cabeçalho, a resposta é
`202` na hora. Num pico, um nó com muitas requisições esperando (`max_waiting_requests`)
responde `202` na hora e não aplica a preferência.

```bash
curl -X POST "$BASE_URL_OCR/v1/extractions" \
  -H "authorization: ApiKey $ACCOUNT:$SECRET" \
  -H "prefer: wait=10" \
  -F "file=@documento.jpg"
```

### Webhooks

Uma empresa cadastra a URL que recebe os eventos (escopo `ocr:write` para criar e remover,
`ocr:read` para listar):

| Método | Rota | Resposta |
|---|---|---|
| `POST` | `/v1/webhook-endpoints` com `{"url": "https://konoha.example/hooks"}` | `201` com `id`, `url`, `secret`, `createdAt`. O `secret` aparece só aqui |
| `GET` | `/v1/webhook-endpoints` | `200` com `data` |
| `DELETE` | `/v1/webhook-endpoints/:id` | `204`; `404` para endpoint de outra empresa |

Quando uma extração chega a um status final, o Aike envia:

```http
POST /hooks
content-type: application/json
aike-event-id: 6f1c…
aike-event-type: extraction.completed
aike-signature: t=1760000000,v1=5f2b…

{"id":"6f1c…","type":"extraction.completed","version":"v1","occurredAt":"…",
 "data":{"id":"<extraction id>","runId":"…","status":"completed"}}
```

Para validar: calcule `HMAC-SHA256(secret, "<t>.<corpo bruto>")` em hexadecimal, compare
com `v1` em tempo constante e recuse `t` com mais de 5 minutos. Responda `2xx` depois de
gravar o evento; repita o mesmo `aike-event-id` sem efeito. Qualquer outra resposta, ou
timeout de 10 s, gera nova tentativa (até 12, com backoff exponencial). O evento não leva
dados pessoais: leia o resultado com `GET /v1/extractions/:id`.

#### Teste manual

`scripts/webhook_receiver.exs` é um receptor local: mostra cada entrega, confere a
assinatura e responde `RESPOND_STATUS` (padrão `204`). No desenvolvimento, o OCR aceita
destino HTTP em `127.0.0.1`.

1. Suba os serviços (`mix phx.server`) e crie uma credencial com `ocr:write,ocr:read`.
2. Cadastre o receptor e guarde o `secret`:

   ```bash
   curl -s http://localhost:4000/v1/webhook-endpoints \
     -H "authorization: ApiKey <accountId>:<secret>" \
     -H "content-type: application/json" \
     -d '{"url":"http://127.0.0.1:4100/hooks"}' | jq
   ```

3. Em outro terminal, suba o receptor com o `secret` do endpoint:

   ```bash
   WEBHOOK_SECRET=whsec_... mix run --no-start scripts/webhook_receiver.exs
   ```

4. Envie uma extração. O receptor mostra o evento com `signature: valid`:

   ```bash
   curl -s http://localhost:4000/v1/extractions \
     -H "authorization: ApiKey <accountId>:<secret>" \
     -F "file=@cnh.pdf" | jq
   ```

Para ver as novas tentativas, suba o receptor com `RESPOND_STATUS=500`: a mesma entrega
(mesmo `aike-event-id`) volta com backoff. Troque para `204` e a próxima tentativa é
entregue. O estado fica em `webhook_deliveries` (`status`, `attempts`,
`last_status_code`):

```bash
psql -h localhost -U kyc -d document_ocr_dev \
  -c "select status, attempts, last_status_code from webhook_deliveries order by inserted_at desc limit 5"
```

### Resposta

Todos os endpoints de extração devolvem o mesmo recurso: o `202` do `POST`, o `GET`, o
`reprocess` e o `cancel`. O `POST` aceito traz o cabeçalho `location`.

```json
{
  "id": "…",
  "runId": "…",
  "status": "requires_confirmation",
  "error": null,
  "document": {"type": "cnh", "country": "BR"},
  "images": [{"side": "single"}],
  "fields": {
    "fullName": {"value": "NARUTO UZUMAKI", "rawValue": "NARUTO UZUMAKI", "confidence": 0.91, "status": "accepted"},
    "cpf": {"value": "52998224725", "rawValue": "529.982.247-25", "confidence": 0.77, "status": "requires_confirmation"},
    "birthDate": {"value": "1990-03-12", "rawValue": "12/03/1990", "confidence": 0.9, "status": "accepted"}
  },
  "createdAt": "…",
  "updatedAt": "…"
}
```

- `status`: `pending`, `processing`, `completed`, `requires_confirmation`, `rejected` ou
  `failed`.
- `error`: `code` e `message`, só quando o status é `failed`.
- `document.type`: o tipo detectado quando o pedido não informou um.
- `fields`: um bloco por campo lido, com o valor normalizado (`value`), o texto lido
  (`rawValue`), a confiança (0 a 1) e o status do campo (`accepted`,
  `requires_confirmation` ou `rejected`). Durante o processamento, `fields` é `{}`.

Campos obrigatórios (decidem o status final) e opcionais (aparecem só quando lidos):

| Documento | Obrigatórios | Opcionais |
|---|---|---|
| CNH | `fullName`, `cpf`, `birthDate` | `identityNumber`, `identityIssuer`, `identityState`, `fathersName`, `mothersName`, `category`, `registrationNumber`, `expirationDate`, `firstLicenseDate`, `issuePlace`, `issueDate` |
| RG | `fullName`, `rgNumber`, `birthDate` | `issueDate`, `fathersName`, `mothersName`, `birthplace`, `originDocument`, `cpf` |

Datas usam ISO 8601 (`1990-03-12`) e CPF só dígitos. Um campo opcional ilegível não
rejeita o documento. RGs antigos não imprimem o CPF.

JSON:

```json
{
  "appId": "konoha",
  "externalId": "user-9876",
  "document": {"type": "cnh", "country": "BR"},
  "images": [
    {
      "side": "front",
      "image": "<base64 dos bytes do documento>",
      "filename": "front.jpg",
      "mimeType": "image/jpeg"
    }
  ]
}
```

Multipart com todos os campos:

```text
externalId=user-9876
documentType=cnh
country=BR
imageFront=<arquivo>
imageBack=<arquivo opcional>
```

JSON e multipart recebem os bytes diretamente. O serviço faz o upload para o
storage interno e cria o `Blob` correspondente. Referências externas via
`source.type=object_storage` são rejeitadas. O JSON exige de uma a duas imagens
com lados distintos (`front`, `back` ou `single`) e base64 não vazio.
`filename` e `mimeType` são opcionais, com defaults `<side>.bin` e
`application/octet-stream`.
Um documento novo retorna `202` com `id`, `runId` e `status`.

### Reutilização por SHA-256

Antes de persistir os uploads ou enfileirar OCR, o serviço calcula o SHA-256 dos
bytes de cada imagem. Se já existe processamento concluído para a mesma empresa,
tipo de documento, país e versões de pipeline/engine/extractor, retorna `200` com
o documento original e seu resultado, no mesmo formato do GET. Não cria documento,
blob ou job adicional; `id` e `runId` permanecem os do processamento reutilizado.
O `externalId` do novo envio não substitui o do documento original.

A comparação considera o conjunto completo de pares lado/hash. A ordem de envio,
nome do arquivo e MIME informado não alteram a identidade do conteúdo. Alterar um
lado, adicionar/remover uma imagem ou mudar os bytes exige novo processamento.

Resultados `completed`, `rejected` e `requires_confirmation` podem ser reutilizados
quando o resultado pertence ao `runId` atual. Estados `failed`, `pending` e
`processing` não são cache de OCR concluído. Recursos em andamento também são
reutilizados com `202`, sem outro job. `idempotency-key` vincula a tentativa ao
recurso e detecta mudanças no payload. O endpoint explícito de
reprocessamento continua disponível para executar novamente.

O estado técnico (`status`) é separado da decisão de negócio (`decision`). Um
documento concluído pode ter `approved`, `rejected` ou `manualReview`.

## Idempotência

Clientes que repetem uma criação devem enviar `idempotency-key`. A chave é limitada
a 256 bytes e é única por empresa e serviço. Mesma chave e mesmo payload devolvem
o recurso vinculado sem criar outro job; payload diferente retorna `409` com
`idempotency_conflict`. Chaves diferentes também podem reutilizar um recurso pelo
hash do conteúdo, mantendo vínculos independentes. Aplica-se a OCR e facematch.

## Retenção

Blobs são armazenados pelo adapter privado configurado pelo serviço. A rotina de
limpeza seleciona somente blobs sem referências. A exclusão do registro ocorre
dentro de uma transação antes de apagar o arquivo; se o storage falhar, o banco
é revertido para permitir retry. Arquivos órfãos e temporários abandonados são
reconciliados a cada cinco minutos após uma carência de uma hora. Recursos de
negócio e seus arquivos referenciados não são apagados só por idade.
Consulte [Idempotência e recuperação](idempotency-and-recovery.md).

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
POST /v1/extractions/:id/cancel
```

Documentos `pending` ou `processing` passam para `failed` com `error_code: "cancelled"`.
Jobs antigos retornam cancelamento quando executados. Um documento terminal não pode
ser cancelado novamente e retorna `409`.
