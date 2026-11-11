# Storage de documentos e métricas de filas

## Persistência

Os bytes dos documentos ficam num storage de objetos privado, nunca no Postgres. O banco
guarda só o `Blob` (chave, SHA-256, tamanho) e as referências. A chave é
`<pasta do serviço>/<sha256>.<extensão>`, então gravar os mesmos bytes duas vezes no mesmo
serviço não duplica nada.

| Adapter | Uso | Seleção |
|---|---|---|
| `AikeStorage.Adapter.S3` | qualquer serviço compatível com S3: Cloudflare R2 em produção, SeaweedFS no desenvolvimento | padrão; `AIKE_STORAGE_ADAPTER=s3` |
| `AikeStorage.Adapter.Local` | disco local (`var/uploads/`, ou `AIKE_UPLOAD_DIR`) | `AIKE_STORAGE_ADAPTER=local` |
| `AikeStorage.Adapter.Fake` | testes | `config/test.exs` |

### Desenvolvimento

`docker compose up -d postgres seaweedfs seaweedfs-init` sobe o SeaweedFS em
`127.0.0.1:8333` e cria o bucket `aike-dev`. As credenciais locais ficam em
`dev/seaweedfs/s3.json` e valem só nessa máquina. O bucket é privado: uma leitura sem
assinatura recebe `403`.

Cada serviço grava na própria pasta do bucket: o OCR em `kyc_documents/` e a biometria
em `facematch/`. O expurgo e a reconciliação de um serviço olham só a pasta dele.

Para ver os arquivos enviados, abra a interface do Filer em
`http://127.0.0.1:8888/buckets/aike-dev/` (porta em `SEAWEEDFS_FILER_PORT`). A interface
não tem login. Por isso a porta fica só em `127.0.0.1`: os arquivos são imagens de
documentos com dados pessoais.

O MinIO não é usado: o projeto foi abandonado, as imagens públicas saíram dos registros
e as versões disponíveis têm falhas de escrita sem autenticação.

### Produção (R2 ou outro S3)

| Variável | Obrigatória | Exemplo |
|---|---|---|
| `S3_ENDPOINT` | sim | `https://<conta>.r2.cloudflarestorage.com` |
| `S3_BUCKET` | sim | `aike-documents` |
| `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` | sim | token de API do R2 com acesso só a esse bucket |
| `S3_REGION` | não | `auto` (padrão, R2) |

Sem essas variáveis o serviço não inicia. As requisições usam URL com o bucket no caminho
e assinatura AWS SigV4, sem novas tentativas: o pipeline controla os retries e os timeouts.

### Pipeline do OCR

O pré-processamento lê cada imagem do storage, confere o SHA-256 com o `Blob` e grava no
artefato só o lado e o ID da imagem. O estágio de OCR lê os bytes do storage de novo.
Artefatos antigos, que ainda têm os bytes em base64, continuam aceitos.

### Retenção e órfãos

`ReconcileStorage` remove blobs vencidos e objetos órfãos (gravados no storage sem
registro no banco, por exemplo numa queda entre o upload e o commit). No S3 a listagem usa
`ListObjectsV2` com o prefixo da pasta do serviço (`kyc_documents/` ou `facematch/`). Objetos com menos de uma hora são ignorados,
para não apagar um upload em andamento.

## Métricas Prometheus

Habilite um token operacional separado em cada serviço e reinicie-o:

```bash
export OCR_METRICS_TOKEN='<token-de-scrape-do-ocr>'
export BIOMETRICS_METRICS_TOKEN='<token-de-scrape-da-biometria>'

curl --fail -sS http://localhost:4000/metrics \
  -H "authorization: Bearer $OCR_METRICS_TOKEN"
curl --fail -sS http://localhost:4002/metrics \
  -H "authorization: Bearer $BIOMETRICS_METRICS_TOKEN"
```

Sem token configurado, retorna `404`; token ausente/incorreto retorna `401`.
Falhas de consulta retornam `503` genérico. O endpoint consulta o banco a cada
scrape, com timeout de cinco segundos. Apenas `GET` é aceito.

- `aike_queue_jobs{service,queue,state}`: quantidade atual de jobs retidos por
  fila e estado. Inclui `available`, `scheduled`, `executing`, `retryable`,
  `completed`, `discarded` e `cancelled`, inclusive valores zero.
- `aike_queue_oldest_ready_age_seconds{service,queue}`: maior tempo desde
  `scheduled_at` entre jobs `available`/`retryable`; datas futuras resultam em zero.

As métricas são gauges, não contadores cumulativos: o Pruner remove jobs terminais.
OCR expõe `preprocess`, `ocr`, `default` e `maintenance`; biometria expõe `biometrics`.
Não há IDs de documentos, empresas, arquivos ou argumentos dos jobs nas labels.
O classifier é síncrono e não possui fila Oban.

Exemplo de configuração Prometheus (ajuste os hosts ao ambiente do coletor):

```yaml
scrape_configs:
  - job_name: aike-ocr
    metrics_path: /metrics
    authorization:
      type: Bearer
      credentials_file: /run/secrets/aike_ocr_metrics_token
    static_configs:
      - targets: ['127.0.0.1:4000']
  - job_name: aike-biometrics
    metrics_path: /metrics
    authorization:
      type: Bearer
      credentials_file: /run/secrets/aike_biometrics_metrics_token
    static_configs:
      - targets: ['127.0.0.1:4002']
```

O token no arquivo do coletor deve corresponder ao token do respectivo serviço.
Este checkpoint disponibiliza o endpoint; não instala um servidor Prometheus.
