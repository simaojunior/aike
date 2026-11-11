# Reconciliação de execuções OCR interrompidas

O worker `DocumentOcr.Workers.ReconcileDocuments` roda a cada cinco minutos em
uma fila `maintenance` com concorrência 1. Cada execução verifica até 100
documentos; lotes seguintes continuam nos próximos ciclos.

Ele corrige documentos `pending` ou `processing` quando existe um job `discarded` ou `cancelled`
do pipeline para o mesmo `document_id` e `run_id`, sem nenhum job `available`,
`scheduled`, `executing` ou `retryable` dessa execução. O documento passa para
`failed`, com código `processing_exhausted` e mensagem genérica. Não dispara
outro OCR nem altera os arquivos.

A verificação final acontece sob lock do documento, relendo o estado e os jobs.
Um reprocessamento que mudou `run_id`, uma conclusão concorrente ou um novo job
ativo faz a operação ser ignorada. Repetir a reconciliação não altera documentos
já corrigidos. Jobs de outros workers e de execuções anteriores são ignorados.

Os dois serviços que compartilham a tabela Oban mantêm jobs terminais por 24
horas. Registros não terminais sem trabalho ativo também são reconciliados após
uma hora sem atualização, mesmo quando os jobs já foram removidos.
Jobs `executing`, `available`, `scheduled` e `retryable` impedem a correção.

Facematch tem recuperação equivalente em `Biometrics.Reconciliation`, executada
por `Biometrics.Workers.Reconcile` na fila `biometrics_maintenance`. Esse worker
também executa a reconciliação do storage local. Conclusões de facematch repetidas
preservam o primeiro resultado persistido.

A recuperação de arquivos órfãos é descrita em
[Idempotência e recuperação](idempotency-and-recovery.md).

Após corrigido, o documento pode ser reprocessado pelo endpoint já existente:

```text
POST /v1/extractions/:id/reprocess
```

Para uma execução manual no console do serviço:

```elixir
DocumentOcr.Reconciliation.run()
# {:ok, quantidade_corrigida}
```

Falhas de banco retornam erro sanitizado e permitem retry do worker. A rotina
emite `[:aike, :document, :reconciliation]` com a contagem `repaired`, sem dados
dos documentos. A fila `maintenance` também aparece no endpoint `/metrics`.

O scheduler fica desativado em testes; os testes executam o worker explicitamente.
Reinicie a API OCR para ativar a nova fila e o agendamento.
