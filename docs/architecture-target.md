# Arquitetura-alvo e diagnóstico atual

A integração autorizada é `app → backend do cliente → Aike`. A service account pertence
exclusivamente ao backend. O mobile não chama classifier, OCR ou biometria com
credenciais de serviço. O cliente decide o fluxo e mantém o estado de negócio;
o Aike processa documentos e emite resultados técnicos.

## Organização desejada

```text
aike/
├── apps/
│   ├── kyc_core/              # vocabulário e regras puras, sem framework
│   ├── document_classifier/   # síncrono, sem banco
│   ├── document_ocr/          # assíncrono, Ecto + Oban; dono do banco de documentos
│   ├── biometrics/            # facematch e prova de vida; dono do banco de biometria
│   ├── backoffice/            # Repo, banco e release próprios
│   ├── aike_http/             # validação Peri e respostas HTTP compartilhadas
│   ├── aike_auth/             # cliente de identidade interno, sem banco
│   ├── aike_storage/          # blobs por dono (banco e pasta); adapters S3/R2 e local
│   └── aike_observability/    # logs, métricas e correlation ID
├── config/
├── test/                     # apenas integração entre apps e checagem de release
└── mix.exs
```

Testes unitários e de contexto permanecem em `apps/<app>/test`. A pasta `test/`
na raiz é um destino futuro: ainda não existe nem é executada automaticamente
pelo runner de testes do umbrella. As checagens de release estão em `scripts/`.
Prova de vida também é escopo futuro; biometria implementa facematch fake.

## Fronteiras implementadas

- `kyc_core`: vocabulário, scopes, fingerprints e funções puras; sem Ecto, Plug ou Phoenix.
- `backoffice`: único proprietário de empresas, service accounts e seus hashes.
  Banco `backoffice_<ambiente>`, Repo e release próprios. `BACKOFFICE_DATABASE_URL`
  é obrigatório em produção, sem fallback para o banco de processamento.
- `document_classifier`: síncrono, sem Repo, SQL, Oban ou cache persistido.
  Peri valida os inputs; seu adapter opcional de Ecto pode acompanhar a release.
  Cada chamada executa o engine. A tabela antiga `classification_results` fica
  preservada no banco de processamento, sem leitores ou escritores nesta versão.
- OCR e biometria: cada um tem banco, Repo, Oban, migrations e tabela `blobs` próprios
  (`document_ocr_<ambiente>` e `biometrics_<ambiente>`). Podem rodar em máquinas
  separadas, com bancos separados.
- `aike_storage`: cada serviço declara um dono (`AikeStorage.Owner`): Repo, pasta no
  bucket (`kyc_documents` para o OCR, `facematch` para a biometria) e as colunas que
  referenciam seus blobs. Expurgo e reconciliação olham só as tabelas e a pasta do dono.
  Assim um serviço nunca apaga arquivos do outro, mesmo com um bucket só.
- `aike_observability`: helper de logs e métricas sem dependência de Ecto; recebe
  um Repo do consumidor para consultar filas.
- `aike_auth`: cliente HTTP e Plug de autenticação, sem banco. É uma lib
  explícita, necessária para não colocar infraestrutura de identidade no core.

O fluxo público permanece `app → backend do cliente → Aike`. O backend apresenta a ApiKey;
o serviço Aike consulta o backoffice para validar a identidade, sem acessar suas
tabelas. O backoffice retorna somente account ID, company ID e scopes; conta ou
empresa inativa é recusada. Cada processador guarda as respostas válidas em cache por
`AIKE_AUTH_CACHE_TTL_SECONDS` (0 a 300); com 0, a revogação vale na próxima consulta.
Uma requisição já autenticada pode terminar após revogação. Indisponibilidade da
identidade resulta em 503, nunca em acesso anônimo.

A dependência de disponibilidade do backoffice é explícita. Introspecção usa timeout
de 3 segundos, conexão de 1 segundo, verificação TLS e não segue redirects.
HTTP sem TLS é aceito em loopback e, com `AIKE_AUTH_ALLOW_HTTP=true`, em qualquer host.
Use essa opção só numa rede privada entre os serviços: a consulta leva o segredo da
credencial.

## Configuração e implantação

Configure o mesmo `AIKE_AUTH_TOKEN` no backoffice e nos processadores, separado
das service accounts e dos tokens de sessão. Configure `BACKOFFICE_AUTH_URL` nos
processadores com a URL completa, por exemplo:
`https://backoffice.internal/internal/v1/service-accounts/introspect`.
O endpoint recebe POST autenticado por Bearer interno com `accountId` e `secret` e responde `accountId`, `companyId` e `scopes`.
Ele não usa sessões humanas nem retorna hashes. Não exponha o token ao mobile.

Para desenvolvimento com os quatro endpoints locais, exporte `AIKE_AUTH_TOKEN`
antes de `mix phx.server`; a URL padrão usa `http://localhost:4003` e o path acima.
Os tokens de borda legados e secrets de endpoint configurados em runtime continuam
exigidos em produção. As requisições de processamento usam **ApiKey**, inclusive
nas verificações de release; Bearer sozinho não fornece tenant/scopes.

### Um executor de migrations por banco

- `DocumentOcr.Repo`: documentos, Oban, blobs, webhooks e requests de processamento.
  As tabelas antigas de facematch continuam nele, sem leitores nem escritores.
- `Biometrics.Repo`: sessões e resultados de facematch, Oban, blobs e requests.
- `Backoffice.Repo`: empresas, credenciais, usuários, sessões e auditoria administrativa.
- Classifier, storage, autenticação e observabilidade não executam migrations.

```bash
mix ecto.create -r Backoffice.Repo
mix ecto.migrate -r Backoffice.Repo
mix ecto.create -r DocumentOcr.Repo
mix ecto.migrate -r DocumentOcr.Repo
mix ecto.create -r Biometrics.Repo
mix ecto.migrate -r Biometrics.Repo

# Em produção, executar uma vez por banco, antes das releases consumidoras:
_build/prod/rel/backoffice/bin/backoffice eval 'Code.require_file("scripts/migrate.exs")'
_build/prod/rel/document_ocr/bin/document_ocr eval 'Code.require_file("scripts/migrate.exs")'
_build/prod/rel/biometrics/bin/biometrics eval 'Code.require_file("scripts/migrate.exs")'

# Verificação de dependências, sem iniciar serviços ou acessar banco:
mix run --no-start scripts/check_boundaries.exs
```

As migrations históricas são preservadas. `scripts/migrate.exs` recusa releases
consumidoras. Migrations não rodam automaticamente ao iniciar o serviço. Mudanças
no banco compartilhado devem ser compatíveis com releases antigas e novas; só
remover estruturas depois de retirar todos os consumidores antigos.

### Instalações em que a biometria usa o banco do OCR

Antes desta versão, a biometria usava o banco do OCR e gravava na pasta
`kyc_documents`. Para separar uma instalação existente, numa janela sem tráfego de
biometria:

1. crie o banco da biometria e rode as migrations dela;
2. copie `facematch_sessions`, `facematch_results`, as linhas de `processing_requests`
   com `service = 'facematch'` e os `blobs` que essas sessões referenciam, preservando
   os UUIDs e as chaves;
3. só então ligue a biometria ao banco novo.

Os blobs copiados ainda têm chaves em `kyc_documents/`, a pasta do OCR. O OCR apaga os
arquivos dessa pasta que o banco dele não referencia, então eles se perderiam. Antes de
ligar a biometria ao banco novo, copie esses arquivos para `facematch/<sha256>.<ext>` e
atualize a coluna `key` dos blobs no banco da biometria. As cópias antigas em
`kyc_documents/` são removidas depois pela reconciliação do OCR.

### Instalações que já usam o banco único

Trocar a configuração não transfere dados. Antes de apontar o backoffice ao novo
banco, faça backup e migre os dados administrativos preservando UUIDs e hashes:
`companies`, `service_accounts`, `backoffice_users`, `backoffice_sessions`,
`backoffice_tokens`, `backoffice_auth_limits` e `backoffice_audit_events`.
Crie o schema novo pelas migrations do backoffice e importe os dados respeitando
FKs, durante uma janela sem escritas administrativas. Não copie o registro completo
`schema_migrations` do banco compartilhado: ele inclui versões do OCR.

Valide contagens, vínculos, login e introspecção no novo banco antes da troca.
Atualize os processadores para a introspecção e então altere o backoffice. Mantenha
as tabelas antigas para rollback até validar o corte; esta mudança não apaga nem
migra automaticamente os dados existentes. UUIDs de empresa nos documentos são
identidades externas, sem FK entre bancos. Não gere empresas novas para substituir
as antigas, pois isso perderia o vínculo de tenant com os documentos existentes.

## Upload delegado proposto — ainda não implementado

1. O app solicita ao backend do cliente o envio de um documento.
2. Backend autentica o usuário e solicita ao Aike uma autorização de upload.
3. Aike reserva um identificador e emite token de curta duração limitado à empresa,
   documento, lado, tamanho máximo e tipo de conteúdo. O token não permite classificar,
   consultar resultados ou reprocessar documentos.
4. Mobile envia os bytes uma vez ao endpoint de upload autorizado. A exceção ao fluxo
   via backend é somente o transporte dos bytes, sem service account no dispositivo.
5. Backend finaliza o envio; Aike valida os arquivos, consome a autorização de forma
   atômica e agenda o processamento. Expiração e reconciliação removem uploads órfãos.

Não aceitar paths de arquivos ou referências arbitrárias enviadas pelo cliente.
Retentativas de finalização precisam ser idempotentes. Com R2/S3, uma URL pré-assinada
pode substituir o transporte local mantendo a autorização e a finalização no Aike.

## Webhook

Implementado no `document_ocr` (`DocumentOcr.Webhooks`). A transição para um status final
(`completed`, `requires_confirmation`, `rejected` ou `failed`, inclusive cancelamento,
esgotamento de retries e cada nova execução de reprocessamento) grava uma entrega de
outbox por endpoint ativo da empresa, na **mesma transação** do documento. Um índice único
por endpoint, documento, execução e tipo de evento impede emissão duplicada lógica.

Envelope: `id` (ID do evento), `type` (`extraction.completed`), `version` (`v1`),
`occurredAt` e `data` com `id`, `runId` e `status`. O evento não leva imagens nem dados
pessoais; o backend consulta o resultado autenticado por GET.

O worker `DeliverWebhook` (fila `webhooks`, 12 tentativas com backoff exponencial) entrega
ao endpoint cadastrado pela empresa em `/v1/webhook-endpoints`, sem aceitar callback
arbitrário por request e sem seguir redirecionamentos. Em produção, só `https` e nenhum
endereço de rede privada (o host é resolvido antes de cada tentativa). A assinatura
`aike-signature: t=<unix>,v1=<HMAC-SHA256>` cobre timestamp e corpo bruto, com um segredo
por endpoint, distinto da service account. Para trocar o segredo, cadastre um endpoint
novo e remova o antigo. Cada tentativa mantém o `aike-event-id` e recebe novo
timestamp e assinatura.

O backend do cliente grava o evento em `provider_events`, com unicidade por provedor e
`event_id`, antes de responder 2xx. Duplicatas válidas recebem 2xx; processamento de
negócio ocorre pelo inbox. Eventos atrasados de outro `run_id` não sobrescrevem a
execução atual. Entrega é pelo menos uma vez, com timeout, backoff e retries; não se
promete entrega exatamente uma vez. Entregas que esgotam as tentativas ficam como `failed`
no banco; ainda não há endpoint para reenviá-las.

GET permanece para diagnóstico e reconciliação, não como loop normal de integração.
A implementação e os testes do inbox pertencem ao repositório do cliente e não foram
alterados nesta revisão.
