> O backoffice agora usa banco próprio (`backoffice_<ambiente>`) e exige
> `BACKOFFICE_DATABASE_URL` em produção, sem fallback. A validação das service
> accounts pelos processadores usa introspecção HTTP interna e `AIKE_AUTH_TOKEN`.
> Consulte [configuração e migração de dados existentes](architecture-target.md#configuração-e-implantação).

# Backoffice independente

API administrativa em loopback na porta 4003, com Application, Repo, migrations e
release próprios. Não depende de OCR, classifier, biometria ou Oban.

## Iniciar e criar o primeiro administrador

Dentro do ambiente Nix:

```bash
cd apps/backoffice
mix ecto.create -r Backoffice.Repo
mix ecto.migrate -r Backoffice.Repo
export BACKOFFICE_BOOTSTRAP_TOKEN="$(openssl rand -hex 32)"
mix phx.server
```

`PGPORT` configura o PostgreSQL (5432 por padrão) e `BACKOFFICE_PORT` altera a
porta HTTP. O token deve ter pelo menos 32 bytes e só autoriza
`POST /v1/auth/bootstrap`. O nome antigo `BACKOFFICE_ADMIN_TOKEN` é aceito como
fallback de configuração para migração, com a mesma restrição: não autoriza
provisionamento ou outras rotas.

Envie este JSON ao bootstrap usando `authorization: Bearer <token-de-bootstrap>`:

```json
{
  "companyName": "Konoha",
  "name": "Administrador da plataforma",
  "email": "admin@example.com",
  "password": "<senha longa, exclusiva, com pelo menos 15 caracteres>"
}
```

Use um arquivo de credenciais com acesso restrito, fora do repositório, para evitar
gravar a senha no histórico do shell:

```bash
curl --fail-with-body -sS http://localhost:4003/v1/auth/bootstrap \
  -H "authorization: Bearer $BACKOFFICE_BOOTSTRAP_TOKEN" \
  -H 'content-type: application/json' \
  --data-binary @/caminho-seguro/bootstrap.json
```

A operação cria a empresa dona da plataforma e o primeiro `platform_admin`
atomicamente. Só funciona se não houver nenhum usuário. Um lock no banco
serializa bootstraps concorrentes. Após o sucesso, remova o token do ambiente do
servidor e reinicie; tentativas posteriores retornam `409 already_bootstrapped`.
A aplicação funciona normalmente sem token de bootstrap configurado.

## Sessões e autenticação

`POST /v1/auth/login` recebe `{"email":"...","password":"..."}` e retorna:

```json
{
  "accessToken": "<token-opaco>",
  "refreshToken": "<token-opaco>",
  "expiresIn": 600,
  "tokenType": "Bearer"
}
```

Use `authorization: Bearer <accessToken>` nas rotas protegidas. Os tokens são
aleatórios (256 bits); só SHA-256 é persistido. O access expira em 10 minutos.
O refresh expira em até 14 dias; a sessão tem limite absoluto de 30 dias.

`POST /v1/auth/refresh` recebe `{"refreshToken":"..."}` e retorna outro par.
A rotação invalida o access anterior. Reutilizar um refresh consumido revoga a
sessão inteira, inclusive em concorrência. Clientes devem serializar o refresh;
em caso de resposta perdida, uma repetição exige novo login.

| Rota | Comportamento |
| --- | --- |
| `GET /v1/auth/me` | Usuário atual e escopos efetivos |
| `POST /v1/auth/logout` | Revoga a sessão atual |
| `POST /v1/auth/logout-all` | Revoga todas as sessões do usuário |
| `POST /v1/auth/password` | Recebe `currentPassword` e `newPassword`; revoga todas as sessões |
| `GET /v1/users` | Até 100 usuários visíveis ao administrador |
| `POST /v1/users` | Cria usuário com `name`, `email`, `password`, `role` e `companyId` opcional |
| `PATCH /v1/users/:id` | Altera somente `role` e `active`; revoga sessões do usuário |
| `POST /v1/companies` | Cria empresa com `name`; somente administrador da plataforma |
| `POST /v1/service-accounts` | Cria credencial M2M na empresa autorizada; segredo retornado uma vez |

Logout e troca de senha retornam `{"ok":true}`. Usuários retornam somente
`id, companyId, name, email, role, active, scopes`; a listagem usa `{"data":[...]}`.
As respostas de empresa e service account mantêm o contrato anterior,
sem discriminador `object`. Todas as respostas do backoffice usam
`cache-control: no-store`.

## Papéis e escopos

- `platform_admin`: administra empresas e usuários da plataforma.
- `company_admin`: administra usuários e cria service accounts somente da própria empresa.
- `company_user`: acessa o próprio perfil e troca a própria senha.

Pertencer à empresa dona **não** concede administração da plataforma. Somente um
`platform_admin` pode atribuir esse papel, e apenas a usuários da empresa dona.
O último administrador ativo não pode ser desativado ou rebaixado.

Escopos são derivados dos papéis no servidor; campos `scopes` enviados ao criar
usuários não concedem privilégios. A semântica inspirada no Oke usa pontos e
wildcard de um segmento: `users.*` cobre `users.read`, mas não
`users.sessions.revoke`. Os papéis recebem concessões explícitas. Alguns escopos
de consulta/revogação de service accounts ficam reservados para endpoints futuros.

Os escopos M2M existentes (`ocr:read`, `classifier:write`, etc.) continuam
separados. Service accounts não autenticam humanos no backoffice.
As permissões e a empresa ativa são consultadas no banco; um objeto de usuário
antigo não permite contornar uma mudança de papel.

## Segurança e limites desta etapa

Senhas usam Argon2id com 32 MiB, duas passagens e uma via; mínimo de 15 caracteres
e máximo de 1024 bytes. Login inválido retorna o mesmo erro para usuário ausente,
senha incorreta e conta desativada, com verificação Argon2 também para usuário
ausente. O banco limita login a 10 tentativas por email e endpoints de autenticação
a 60 por IP em janelas de 5 minutos. O IP vem do socket; um proxy compartilhado
compartilha esse limite até haver configuração explícita de proxies confiáveis.

Há auditoria de bootstrap, criação/alteração de usuários e provisionamento, sem
senhas ou tokens. A API usa Bearer explícito, sem autenticação por cookie.
Para exposição externa, use HTTPS. MFA, recuperação de senha, convites, interface
visual e limpeza periódica de sessões expiradas/limites ficam para próximos
checkpoints. Não há JWT nesta etapa: sessões opacas no banco permitem revogação
imediata sem adicionar um serviço de autenticação separado.

Erros usam `application/problem+json` e `{code, detail, errors?}`, conforme o
[contrato comum](api-errors.md). Peri valida os inputs antes do domínio e do Ecto.
O identificador de correlação permanece no header `x-request-id`.

| Status | Códigos |
| --- | --- |
| 400 | `bad_request`, `invalid_json` |
| 401 | `unauthorized`, `invalid_credentials` (replay também retorna `unauthorized`) |
| 403 | `forbidden` |
| 404 | `not_found`, `company_not_found` |
| 409 | `already_bootstrapped`, `last_platform_admin`, `conflict` |
| 413 / 415 | `payload_too_large` / `unsupported_media_type` |
| 422 | `validation`, `invalid_request`, `invalid_password` |
| 429 | `rate_limited`, com `retry-after: 300` |

## Banco, CLI e release

O banco administrativo é separado. `BACKOFFICE_DATABASE_URL` é obrigatório em
produção, sem fallback para `DATABASE_URL`. Os processadores validam service
accounts por introspecção HTTP e não acessam tabelas administrativas. Cada processador
guarda uma identidade válida por até `AIKE_AUTH_CACHE_TTL_SECONDS` (padrão 30 s): desativar
uma service account ou uma empresa só vale em todos os nós depois desse tempo. Instalações
antigas precisam transferir os dados preservando UUIDs e hashes, conforme o
[procedimento de migração](architecture-target.md#instalações-que-já-usam-o-banco-único).

As migrations originais de empresas e service accounts mantêm os timestamps.
A migration de identidade acrescenta usuários, sessões, tokens, limites e
auditoria. Somente a release OCR executa as migrations do banco de processamento.

Os comandos `mix aike.company.create` e `mix aike.service_account.create` continuam
disponíveis para operações locais com acesso direto ao banco. Não representam
sessões de usuário e devem ficar restritos a operadores com acesso ao host.

```bash
MIX_ENV=prod mix release backoffice
export BACKOFFICE_DATABASE_URL='postgres://usuario:senha@localhost/banco'
export BACKOFFICE_SECRET_KEY_BASE='<segredo-de-pelo-menos-64-caracteres>'
export AIKE_AUTH_TOKEN='<segredo-interno-compartilhado-com-processadores>'
PHX_SERVER=true _build/prod/rel/backoffice/bin/backoffice start
```

Produção exige banco, secret key próprio e `AIKE_AUTH_TOKEN`; não exige credenciais dos serviços de
processamento nem o token de bootstrap após a inicialização. Em um banco vazio de
verificação, com as migrations aplicadas, este comando testa a release isolada e
desfaz as gravações:

```bash
_build/prod/rel/backoffice/bin/backoffice eval 'Code.eval_file("scripts/check_backoffice_release.exs")'
```
