# Contrato de respostas HTTP

Backoffice, classifier, OCR e biometria compartilham o contrato de erros de
`aike_http`. Todos validam inputs com Peri antes de chamar o domínio ou persistir
com Ecto. Ecto permanece responsável pelas restrições de persistência.

Erros retornam `content-type: application/problem+json` e `cache-control: no-store`:

```typescript
type FieldIssue = { readonly field: string; readonly detail: string };
type ProblemDetails = {
  readonly code: string;
  readonly detail: string;
  readonly errors?: readonly FieldIssue[];
};
```

O código é estável em snake_case; `detail` é uma descrição humana em inglês.
Clientes devem decidir pelo status HTTP e por `code`, sem comparar textos.
O status fica na resposta HTTP. `errors` aparece nas falhas de validação Peri.
Campos aninhados usam pontos e índices a partir de zero, como `images.0.image`.
Valores recebidos, senhas, tokens, SQL e stack traces não são serializados.
A correlação com logs usa o header `x-request-id`.

Exemplo de senha curta no bootstrap (HTTP 422):

```json
{
  "code": "validation",
  "detail": "One or more request fields are invalid.",
  "errors": [{"field": "password", "detail": "Must contain at least 15 characters."}]
}
```

| Status | Situação / código |
| --- | --- |
| 400 | JSON malformado: `invalid_json`; corpo inválido: `bad_request` |
| 401 | `unauthorized`, `invalid_credentials`; inclui `www-authenticate` |
| 403 | `forbidden` |
| 404 | `not_found`, `company_not_found` |
| 409 | `conflict`, `idempotency_conflict`, `already_bootstrapped`, `last_platform_admin` |
| 413 / 415 | `payload_too_large` / `unsupported_media_type` |
| 422 | `validation` para inputs; demais rejeições de domínio têm código próprio |
| 429 | `rate_limited`, com `retry-after` |
| 500 | `internal_server_error`, descrição fixa `Internal server error.` |
| 503 | `service_unavailable` |

### Arquivo recusado pela classificação

| Status | `code` | Quando | O que fazer |
| --- | --- | --- | --- |
| 413 | `file_too_large` | arquivo acima de 10 MB | reduza a qualidade ou a resolução |
| 415 | `unsupported_file` | formato fora de JPEG, PNG e PDF (HEIC, WEBP, GIF), imagem animada ou arquivo corrompido | converta para JPEG ou PNG |
| 422 | `image_too_large` | PNG acima de 20 megapixels, ou JPEG acima de cerca de 1,28 gigapixel | envie em JPEG, ou reduza a imagem |
| 422 | `unsupported_page_count` | PDF com mais de uma página | envie só a página do documento |

Um JPEG acima de 20 megapixels, como uma foto de celular de 48 MP, é aceito: o serviço o
lê já reduzido a 1/2, 1/4 ou 1/8, sem carregar a imagem inteira na memória. O PNG não
tem leitura reduzida, por isso fica limitado a 20 megapixels. Os limites protegem a
memória contra imagens que se expandem demais ao abrir.

UUID malformado retorna 422; UUID válido de recurso inexistente retorna 404.
Headers idempotency-key presentes nos processadores devem conter um único valor
com 1 a 256 bytes. Autenticação precede a validação de campos nas rotas protegidas.

Sucessos preservam os corpos dos recursos: 200 nas consultas e operações síncronas,
201 com `location` na criação administrativa e 202 na aceitação de processamento
assíncrono. O endpoint de métricas mantém o formato Prometheus.

Esta mudança substitui os antigos envelopes `{error: ...}`. Clientes devem migrar
para `code`, `detail` e `errors`; não há envelope legado em paralelo.
