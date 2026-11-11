# Reprocessamento com identidade de execução — checkpoint 5

```http
POST /v1/extractions/:id/reprocess
content-type: application/json

{"pipelineVersion":"2026.11.0"}
```

Resposta 202:

```json
{"id":"document-uuid","run_id":"new-run-uuid","status":"pending"}
```

POST de criação, GET de documento e GET de resultado também retornam `run_id`.
O consumidor pode comparar esse identificador durante o polling e detectar que
outro pedido iniciou uma execução mais recente. Imagens, `appId`, `externalId` e
document ID são preservados; request_id é atualizado para correlacionar a nova execução.

## Versões e respostas

- Esta versão aceita somente o `pipelineVersion` ativo em configuração. A nova
  execução captura engine e versões ativas pelos mesmos registros do checkpoint 4.
  Não se executa o código atual sob uma versão desconhecida ou histórica.
- Corpo incompleto, valor inválido ou versão não suportada: 422.
- Documento inexistente ou UUID inválido, com versão válida: 404.
- Configuração ativa de processamento indisponível: 503 genérico.
- Reprocessamento aceito: 202 pending, inclusive a partir de processing ou estados terminais.
- GET result responde 409 enquanto a nova execução não possui resultado terminal;
  nunca entrega o resultado anterior como se pertencesse à execução atual.
- As mesmas regras de autenticação da API OCR se aplicam ao novo endpoint.

## Garantias e política de concorrência

O contexto obtém um lock do documento e, numa única transação curta:

1. Remove os artefatos e o resultado anteriores.
2. Cria um UUID de execução, grava a configuração capturada, redefine pending
   e limpa os erros, por meio do Processor.
3. Insere PreprocessDocument com `{document_id, run_id}`.

Se a transação/enqueue falhar, o documento, os outputs e os jobs anteriores são
restaurados por rollback. Todos os cinco workers propagam run_id. Os critérios de
unicidade do Oban já incluem args, separando jobs de execuções diferentes.

O worker compara run_id antes de processar e novamente sob lock; o tratamento de
falhas também faz essa comparação. Jobs antigos retornam cancelamento `stale_run`,
inclusive na última tentativa. Não fazem OCR, não criam o próximo job e não mudam
o status da execução nova. Escritas pelo contexto e transições também recusam
structs antigos com `{:error, :stale_run}`. FKs compostas no banco garantem que
artefatos/resultados pertençam à execução atual de seu documento.

Storage e OCR rodam fora de qualquer transação que mantenha o lock do documento.
O worker marca processing em uma transação curta, executa a chamada externa e só
depois abre outra transação curta para validar run_id, persistir o artefato e inserir
o próximo job. O reprocessamento pode obter o lock enquanto a chamada externa está
bloqueada; troca o run_id e remove outputs. Quando o job antigo termina, sua
persistência encontra stale_run e é cancelada, sem sobrescrever a nova execução.
Não há cancelamento do run por remoção de dados: o adapter termina ou esgota timeout e
o resultado é descartado pela proteção de run_id.

Pedidos simultâneos são serializados: cada pedido aceito ganha um run_id e o último
a obter o lock fica vigente. Um POST repetido inicia outra execução; ainda não existe
idempotency key de HTTP nem comparação condicional do run_id esperado pelo cliente.
Jobs obsoletos na fila são cancelados quando executados; não há remoção antecipada.

## Persistência e atualização

Permanece o desenho de **um resultado atual por documento**, sem histórico. Reprocessar
substitui deliberadamente os artefatos/resultados atuais. Retenção de resultados antigos
exige tabela de histórico e política separadas; Oban não é um histórico de resultados.

A migration `20261005000002_add_processing_runs` adiciona run_id a documents,
document_artifacts e document_results. Registros existentes recebem uma identidade
e seus artefatos/resultados são vinculados a ela, sem modificar os campos extraídos
ou presumir versões de engine que não tinham sido registradas.

```bash
mix ecto.migrate
MIX_ENV=test mix ecto.migrate
```

Pare os workers antigos durante a atualização e aplique a migration antes do código
novo. Jobs legados sem run_id são cancelados, pois não podem ser associados com
segurança à execução atual. Para documentos antigos pendentes, use reprocessamento
após atualizar; isso também captura versões antes ausentes. Não há retomada automática
de jobs legados nem suporte a misturar workers de antes/depois desta migration.

## Verificação

Testes cobrem endpoint, versão inválida, nova configuração, resultado único, jobs
obsoletos/retries, structs antigos, recuperação de documento failed/legado, rollback
e FKs. Os testes de concorrência usam conexões PostgreSQL distintas e verificam
`pg_blocking_pids`, sem simular concorrência numa conexão compartilhada do sandbox.
Eles cobrem sucesso em andamento, falha final concorrente e dois pedidos simultâneos,
com limpeza dos registros de teste criados fora do sandbox.

Com `mix phx.server` iniciado, execute na raiz:

```bash
bash scripts/smoke-reprocess.sh
```

O script cria um documento fake, aguarda completed, reprocessa e confirma completed
com run_id novo e resultado canônico. Deixa apenas esse documento de demonstração
no banco local. `OCR_URL` e `PIPELINE_VERSION` permitem ajustar URL e versão ativa.

Verificação executada: migration aplicada em dev/test, `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix test` (**58 testes: 38 OCR, 19 classifier,
1 core**) e `mix phx.routes DocumentOcrWeb.Router`. O smoke HTTP completou as duas
execuções com run_id distintos. Os testes de concorrência também confirmaram que
storage bloqueado não impede o reprocessamento de obter o lock e que o job antigo
é cancelado ao persistir. Nenhuma falha restante nas verificações executadas.
