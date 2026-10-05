# Timeouts e cancelamento de jobs

Chamadas de storage e OCR são executadas fora da transação que atualiza o documento.
Em produção elas usam tarefas isoladas com limites configuráveis:

```elixir
config :document_ocr,
  storage_timeout_ms: 5_000,
  ocr_timeout_ms: 15_000,
  external_call_mode: :async
```

Um timeout retorna `{:error, :timeout}`. O worker devolve erro sanitizado ao Oban para
retry; enquanto ainda houver tentativas, o documento permanece `processing`. Na última
tentativa, a transição é `failed`, com `error_code: "processing_timeout"`.

O modo `:sync` existe apenas para testes que precisam preservar o processo chamador.
Jobs de uma execução antiga são cancelados por `run_id` antes de cada estágio e também
antes de persistir o resultado. Portanto, um timeout ou resultado tardio não pode
sobrescrever uma reprocessamento mais novo.
