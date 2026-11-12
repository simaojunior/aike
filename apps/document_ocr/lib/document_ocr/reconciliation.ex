defmodule DocumentOcr.Reconciliation do
  @moduledoc "Repairs nonterminal documents whose current run has an exhausted job."
  import Ecto.Query
  alias DocumentOcr.{Documents, Repo}
  alias DocumentOcr.Documents.{Document, Processor}

  @workers ~w(DocumentOcr.Workers.PreprocessDocument DocumentOcr.Workers.OcrDocument
              DocumentOcr.Workers.ExtractFields DocumentOcr.Workers.ValidateFields
              DocumentOcr.Workers.CompleteDocument)
  @active ~w(available scheduled executing retryable)

  def run(limit \\ 100) when is_integer(limit) and limit > 0 and limit <= 1000 do
    limit |> candidates() |> repair_candidates()
  rescue
    _ -> {:error, :reconciliation_failed}
  end

  defp candidates(limit) do
    cutoff = DateTime.add(DateTime.utc_now(), -3600)

    from(document in Document,
      left_join: job in Oban.Job,
      on:
        fragment("?->>'document_id' = ?::text", job.args, document.id) and
          fragment("?->>'run_id' = ?::text", job.args, document.run_id),
      left_join: active in Oban.Job,
      on:
        fragment("?->>'document_id' = ?::text", active.args, document.id) and
          fragment("?->>'run_id' = ?::text", active.args, document.run_id) and
          active.worker in ^@workers and active.state in ^@active,
      where:
        document.status in ["pending", "processing"] and is_nil(active.id) and
          ((job.state in ["discarded", "cancelled"] and job.worker in ^@workers) or
             document.updated_at < ^cutoff),
      distinct: true,
      order_by: document.id,
      limit: ^limit,
      select: {document.id, document.run_id}
    )
    |> Repo.all()
  end

  defp repair_candidates(candidates) do
    Enum.reduce_while(candidates, {:ok, 0}, fn {id, run_id}, {:ok, count} ->
      case reconcile(id, run_id) do
        {:ok, :repaired} -> {:cont, {:ok, count + 1}}
        {:ok, :skipped} -> {:cont, {:ok, count}}
        {:error, _} -> {:halt, {:error, :reconciliation_failed}}
      end
    end)
  end

  def reconcile(id, expected_run_id) do
    Repo.transaction(fn ->
      case Documents.lock(id) do
        %Document{run_id: ^expected_run_id, status: status} = document
        when status in ["pending", "processing"] ->
          repair(document)

        _ ->
          :skipped
      end
    end)
  end

  defp repair(document) do
    jobs =
      from(job in Oban.Job,
        where:
          fragment("?->>'document_id' = ?", job.args, ^document.id) and
            fragment("?->>'run_id' = ?", job.args, ^document.run_id) and job.worker in ^@workers
      )

    if (Repo.exists?(from(j in jobs, where: j.state in ["discarded", "cancelled"])) or
          DateTime.before?(document.updated_at, DateTime.add(DateTime.utc_now(), -3600))) and
         not Repo.exists?(from(j in jobs, where: j.state in ^@active)) do
      case Processor.fail(document, "processing_exhausted", "Processing job exhausted retries") do
        {:ok, _} -> :repaired
        {:error, reason} -> Repo.rollback(reason)
      end
    else
      :skipped
    end
  end
end
