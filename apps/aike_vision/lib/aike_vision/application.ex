defmodule AikeVision.Application do
  @moduledoc """
  Starts the node-wide limits for document processing.

  - `AikeVision.Processes`: Tesseract processes running at once on this node. Each process
    uses one core, so the default is one per scheduler
  - `AikeVision.Documents`: documents processed at once by synchronous callers, with a
    short waiting line. Past it, callers get `{:error, :overloaded}` and answer 503 with
    `Retry-After`. The default is half the schedulers: measured throughput peaks there,
    because each document runs several OCR passes in parallel

  ## Configuration

      config :aike_vision,
        ocr_processes: 20,
        max_documents: 10,
        max_waiting_documents: 20,
        admission_wait_ms: 3_000,
        retry_after_seconds: 2

  In releases, set them with `AIKE_OCR_PROCESSES`, `AIKE_MAX_DOCUMENTS`,
  `AIKE_MAX_WAITING_DOCUMENTS`, `AIKE_ADMISSION_WAIT_MS` and `AIKE_RETRY_AFTER_SECONDS`.
  See `docs/capacity.md`.
  """
  use Application

  @impl true
  def start(_type, _args) do
    cores = System.schedulers_online()
    config = Application.get_all_env(:aike_vision)
    documents = Keyword.get(config, :max_documents, max(1, div(cores, 2)))

    children = [
      {AikeVision.Limiter,
       name: AikeVision.Processes, limit: Keyword.get(config, :ocr_processes, cores)},
      {AikeVision.Limiter,
       name: AikeVision.Documents,
       limit: documents,
       max_waiting: Keyword.get(config, :max_waiting_documents, documents * 2)}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: AikeVision.Supervisor)
  end
end
