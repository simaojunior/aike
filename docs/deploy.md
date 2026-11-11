# Implantação

O Aike é um monolito modular: um repositório umbrella com quatro serviços, e cada serviço
tem release, imagem e banco próprios. No desenvolvimento, `mix phx.server` sobe os quatro
juntos. Em produção, eles podem ficar numa máquina só ou em máquinas separadas. Um
serviço nunca lê o banco de outro: os processadores falam com o backoffice só por HTTP.

| Serviço | Release | Banco | Storage | Precisa no sistema |
|---|---|---|---|---|
| Backoffice (empresas, credenciais) | `backoffice` | `backoffice` | não | nada |
| Extração (OCR) | `document_ocr` | `document_ocr` | sim, pasta `kyc_documents/` | Tesseract com `por`, Poppler |
| Classificação | `document_classifier` | não | não | Tesseract com `por`, Poppler |
| Biometria (facematch) | `biometrics` | `biometrics` | sim, pasta `facematch/` | Poppler e modelos de rosto (já na imagem) |

OCR e biometria podem usar o mesmo bucket: cada um lê, expurga e reconcilia só a sua
pasta.

## Imagens

O `Dockerfile` na raiz gera uma imagem por release:

```bash
docker build --build-arg RELEASE=document_ocr -t aike/document_ocr:1.0.0 .
docker build --build-arg RELEASE=document_classifier -t aike/document_classifier:1.0.0 .
docker build --build-arg RELEASE=biometrics -t aike/biometrics:1.0.0 .
docker build --build-arg RELEASE=backoffice -t aike/backoffice:1.0.0 .
```

Toda imagem:

- roda como o usuário sem privilégio `aike`;
- escuta na porta `4000`, em `0.0.0.0` (`AIKE_HTTP_IP`);
- responde `GET /health` com `200` antes da autenticação, para o orquestrador;
- tem a migration da release em `scripts/migrate.exs`.

As imagens do OCR e do classificador incluem Tesseract, o idioma `por` e Poppler. O
OpenCV vem compilado no próprio NIF do `evision`, para `x86_64` Linux com glibc. As
versões de Elixir e Debian ficam nos `ARG` `ELIXIR_IMAGE` e `RUNTIME_IMAGE`.

## Ordem de subida

1. Bancos: um por serviço com banco (podem ser bancos de um mesmo servidor Postgres).
2. Migrations, uma vez por banco, com a imagem do serviço dono:
   `/app/bin/server eval 'Code.require_file("scripts/migrate.exs")'`.
   Só `document_ocr`, `biometrics` e `backoffice` têm migrations.
3. Backoffice.
4. Processadores (OCR, classificação, biometria). Eles dependem do backoffice para validar
   cada credencial; sem ele, respondem `503`.

As migrations não rodam ao iniciar o serviço. Uma migration nova deve funcionar com a
versão antiga e com a nova do serviço, para permitir troca sem parada.

## Variáveis

### Todos os serviços

| Variável | Obrigatória | Uso |
|---|---|---|
| `PHX_SERVER` | já `true` na imagem | liga o servidor HTTP |
| `AIKE_HTTP_IP` | já `0.0.0.0` na imagem | endereço de escuta; fora da imagem, o padrão é `127.0.0.1` |
| `PORT`, `CLASSIFIER_PORT`, `BIOMETRICS_PORT`, `BACKOFFICE_PORT` | já `4000` na imagem | porta de cada serviço |

### Backoffice

| Variável | Obrigatória | Uso |
|---|---|---|
| `BACKOFFICE_DATABASE_URL` | sim | banco do backoffice; não há fallback para outro banco |
| `BACKOFFICE_SECRET_KEY_BASE` | sim | segredo do endpoint, no mínimo 64 bytes |
| `AIKE_AUTH_TOKEN` | sim | token interno da introspecção, igual em todos os serviços |
| `BACKOFFICE_BOOTSTRAP_TOKEN` | só na primeira subida | cria o primeiro administrador, no mínimo 32 bytes; remova depois |

### Processadores (OCR, classificação, biometria)

| Variável | Obrigatória | Uso |
|---|---|---|
| `AIKE_AUTH_TOKEN` | sim | o mesmo do backoffice |
| `BACKOFFICE_AUTH_URL` | sim | URL completa da introspecção, por exemplo `https://backoffice.internal/internal/v1/service-accounts/introspect` |
| `AIKE_AUTH_ALLOW_HTTP` | não | `true` aceita a URL acima em HTTP; use só numa rede privada |
| `AIKE_AUTH_CACHE_TTL_SECONDS` | não | cache das credenciais válidas, de 0 a 300 (padrão 30) |

### Extração (OCR)

| Variável | Obrigatória | Uso |
|---|---|---|
| `DATABASE_URL` | sim | banco do OCR |
| `SECRET_KEY_BASE` | sim | segredo do endpoint, no mínimo 64 bytes |
| `SERVICE_TOKEN` | sim | token Bearer legado da borda; gere um valor aleatório |
| `WEBHOOK_SIGNING_KEY` | sim | chave das assinaturas de webhook, no mínimo 32 bytes |
| `S3_ENDPOINT`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | sim | bucket privado (R2 ou outro S3) |
| `S3_REGION` | não | padrão `auto` |
| `OCR_QUEUE_CONCURRENCY` | não | documentos lidos ao mesmo tempo no nó |
| `OCR_METRICS_TOKEN` | não | liga `GET /metrics` (Prometheus) com esse Bearer |

### Classificação

| Variável | Obrigatória | Uso |
|---|---|---|
| `CLASSIFIER_SECRET_KEY_BASE` | sim (ou `SECRET_KEY_BASE`) | segredo do endpoint, no mínimo 64 bytes |
| `CLASSIFIER_SERVICE_TOKEN` | sim (ou `SERVICE_TOKEN`) | token Bearer legado da borda |

### Biometria

| Variável | Obrigatória | Uso |
|---|---|---|
| `BIOMETRICS_DATABASE_URL` | sim | banco da biometria; não há fallback para o banco do OCR |
| `BIOMETRICS_SECRET_KEY_BASE` | sim (ou `SECRET_KEY_BASE`) | segredo do endpoint |
| `BIOMETRICS_SERVICE_TOKEN` | sim (ou `SERVICE_TOKEN`) | token Bearer legado da borda |
| `S3_*` | sim | as mesmas do OCR; o bucket pode ser o mesmo |
| `BIOMETRICS_METRICS_TOKEN` | não | liga `GET /metrics` |
| `AIKE_FACE_MODELS_DIR` | já `/app/models` na imagem | pasta dos modelos de rosto; veja [Facematch](facematch.md) |

Os limites de CPU e de fila (`AIKE_OCR_PROCESSES`, `AIKE_MAX_DOCUMENTS` e outros) estão em
[Capacidade](capacity.md).

Gere segredos com `openssl rand -base64 48` (64 caracteres). Uma variável obrigatória
ausente ou vazia impede o serviço de iniciar.

## Exemplo: tudo numa máquina

`deploy/docker-compose.yml` sobe os quatro serviços, um Postgres com os três bancos e um
SeaweedFS como S3. Cada serviço é um container próprio e só se comunica com os outros
pela rede.

```bash
cd deploy
./generate-env.sh
docker compose up -d --build
docker compose ps
```

`generate-env.sh` cria o `deploy/.env` a partir do `.env.example`, com permissão `600` e
um segredo aleatório de 64 caracteres no lugar de cada `change-me`. O arquivo fica fora
do Git. As credenciais do S3 do exemplo valem só para o SeaweedFS local.

As portas ficam só em `127.0.0.1`: OCR `4000`, classificação `4001`, biometria `4002`,
backoffice `4003`. Na frente, use um proxy com HTTPS (Caddy, Nginx ou o balanceador da
nuvem).

Depois da primeira subida, crie o primeiro administrador, a empresa e a service account
pela API do backoffice: veja [Backoffice](backoffice.md). As `mix tasks` de
provisionamento só existem no ambiente de desenvolvimento.

## Separar em máquinas

Para levar um serviço para outra máquina, mude só as variáveis dele:

- `BACKOFFICE_AUTH_URL`: o endereço do backoffice visto pela nova máquina. Use HTTPS;
  `AIKE_AUTH_ALLOW_HTTP=true` só dentro de uma rede privada (VPC, VPN);
- `DATABASE_URL` / `BIOMETRICS_DATABASE_URL`: o servidor de banco do serviço;
- `S3_*`: o mesmo bucket ou outro.

**Mais nós de OCR.** Vários nós de OCR podem usar o mesmo banco: o Oban distribui os jobs
entre eles, e cada nó limita o próprio uso de CPU. O classificador não tem estado; basta
pôr mais nós atrás do balanceador. Veja [Capacidade](capacity.md) para dimensionar.

## Proxy e HTTPS

- Termine o HTTPS no proxy e encaminhe em HTTP/1.1 para os serviços, na rede privada.
  O Bandit 1.12.5 tem um alerta de segurança no HTTP/2, e o HTTP/1.1 evita esse risco
  até a correção.
- Não exponha o backoffice à internet se não for necessário. Os processadores só
  precisam do caminho de introspecção.
- O webhook do OCR exige destino HTTPS e recusa endereços privados em produção.

## Limitações conhecidas

- `prefer: wait` com vários nós de OCR usa `LISTEN/NOTIFY` do Postgres e ainda não foi
  testado entre nós.
- As imagens são só `x86_64`.
- A imagem usa o Tesseract do Debian (5.5.0); o ambiente Nix usa o 5.5.2. A leitura pode
  mudar um pouco entre versões, então meça o acerto com a mesma imagem que vai para
  produção.
- Não há pipeline de CI no repositório.
