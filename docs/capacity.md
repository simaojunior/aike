# Capacidade e picos de requisições

O OCR é limitado pela CPU. Cada passada do Tesseract é um processo com uma thread e ocupa
um núcleo. Mais requisições do que a CPU suporta não aumentam a vazão: só aumentam a
latência e a memória. Por isso cada nó tem limites explícitos.

## Limites por nó

| Variável | Padrão | O que limita |
|---|---|---|
| `AIKE_OCR_PROCESSES` | um por scheduler (núcleo lógico) | processos Tesseract ao mesmo tempo no nó, para todos os documentos |
| `AIKE_MAX_DOCUMENTS` | metade dos schedulers | documentos do classificador em processamento ao mesmo tempo |
| `AIKE_MAX_WAITING_DOCUMENTS` | 2 × `AIKE_MAX_DOCUMENTS` | fila de espera do classificador |
| `AIKE_ADMISSION_WAIT_MS` | 3000 | espera máxima nessa fila |
| `AIKE_RETRY_AFTER_SECONDS` | 2 | valor do cabeçalho `retry-after` na recusa |
| `OCR_QUEUE_CONCURRENCY` | metade dos schedulers | jobs de OCR (fila `ocr` do Oban) ao mesmo tempo |

A metade dos schedulers é o ponto de maior vazão medido: cada documento faz várias
passadas em paralelo, e com mais documentos a disputa pela CPU reduz a vazão.

## Comportamento sob pico

**Classificador (síncrono).** Uma requisição passa por três barreiras:

1. Se a fila de espera do nó já está cheia, `DocumentClassifierWeb.ShedLoad` responde
   `503` com `retry-after` **antes** de ler o corpo e antes da autenticação. O upload não
   entra na memória e o backoffice não recebe a consulta.
2. Senão, a requisição espera uma vaga por até `AIKE_ADMISSION_WAIT_MS`. Sem vaga nesse
   prazo, a resposta é a mesma `503` com `retry-after`.
3. Com vaga, o documento tem até 10 s para terminar. As passadas esperam vagas de
   `AIKE_OCR_PROCESSES`, então o nó nunca roda mais processos do que tem núcleos.

A recusa não gera log de erro por requisição. Ela emite os eventos `:telemetry`
`[:aike_vision, :limiter, :rejected]` e `[:document_classifier, :load_shed]`.

**OCR (assíncrono).** `POST /v1/extractions` só grava o documento e enfileira o job. A
fila do Oban fica no Postgres e absorve o pico. A latência aumenta, mas nenhum documento
falha por excesso de carga. Acompanhe `aike_queue_oldest_ready_age_seconds` no `/metrics`.

**Espera síncrona (`prefer: wait`).** Uma requisição que espera não usa CPU, mas mantém
a conexão aberta. Cada nó aceita até `max_waiting_requests` (padrão 1000) esperando; acima
disso responde `202` na hora. A notificação de conclusão usa `LISTEN/NOTIFY` do Postgres,
e uma leitura a cada `completion_poll_ms` (padrão 1 s) cobre notificações perdidas.

**Autenticação.** Os serviços guardam por `AIKE_AUTH_CACHE_TTL_SECONDS` (padrão 30, de 0 a
300; 0 desliga) cada identidade válida que o backoffice confirmou. Num pico de uma mesma
service account, só a primeira requisição consulta o backoffice; as requisições simultâneas
esperam essa mesma resposta. Credenciais inválidas e falhas do backoffice não ficam no
cache. **Consequência:** uma credencial revogada ou uma empresa desativada continua aceita
em cada nó por até esse tempo. O cache guarda um HMAC da credencial com uma chave criada no
boot, nunca o segredo.

**Clientes.** Ao receber `503` com `retry-after`, o cliente deve esperar pelo menos esse
tempo e repetir com backoff exponencial e jitter. Sem jitter, todos repetem juntos e criam
um novo pico.

## Medições

Máquina: notebook Intel i7-13650HX, 14 núcleos físicos (20 lógicos, núcleos híbridos).
Documentos reais: RG fotografado de lado, o mesmo RG em pé e CNH digital em PDF.

| Medição | Resultado |
|---|---|
| Classificador, um documento | RG em pé 1,0 s; RG de lado 1,5 s; CNH em PDF 0,7 s |
| Classificador, vazão com CPU saturada | 4,4 a 5,7 documentos/s por nó |
| Classificador, 200 requisições ao mesmo tempo | 23 processadas (p95 4,2 s); 177 recusadas em menos de 1 ms (algumas após 3 s de espera); memória da VM 94 MB |
| OCR, vazão com CPU saturada | 2,3 documentos/s por nó; pior caso 7,5 s por documento |

Meça no hardware de produção antes de dimensionar:

```bash
LOAD_FILES=/caminho/rg.jpg,/caminho/cnh.pdf LOAD_REQUESTS=200 \
  mix run scripts/load_classifier.exs
```

## Dimensionamento para um pico de 10 mil requisições

Nós necessários = pico ÷ (vazão por nó × tempo aceitável para atender o pico).

| Serviço | Atender 10 mil em 1 min | Em 5 min | Em 15 min |
|---|---|---|---|
| Classificador (~5 doc/s por nó) | ~34 nós | ~7 nós | ~3 nós |
| OCR (~2,3 doc/s por nó) | ~73 nós | ~15 nós | ~5 nós |

Com menos nós, o classificador recusa o excesso com `503` + `retry-after` e continua
estável. O OCR enfileira o excesso e o processa na ordem. Escale pelo uso de CPU, pela
taxa de recusas e pela idade da fila.

Memória por nó: cada documento em processamento usa até ~60 MB (imagem de 20 milhões de
pixels). Com os padrões em 20 núcleos, 10 documentos e 20 na fila cabem em menos de 1 GB.
Mantenha um limite de conexões no balanceador, porque o corpo de uma requisição aceita
(até 20 MB) é lido antes da admissão.

## Riscos conhecidos

- **Medições em notebook.** Núcleos híbridos e hyperthreading reduzem a vazão por núcleo.
  Servidores com núcleos físicos dedicados devem render mais. Meça antes de dimensionar.
