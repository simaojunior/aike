defmodule DocumentOcr.Application do
  @moduledoc """
  OTP application of the OCR service.

  It starts the repository, the HTTP endpoint, Oban and the completion registry.
  """
  use Application

  def start(_type, _args) do
    children = [
      DocumentOcr.Repo,
      DocumentOcrWeb.Endpoint,
      {Oban, Application.fetch_env!(:document_ocr, Oban)},
      {Registry, keys: :duplicate, name: DocumentOcr.Completion.Registry},
      DocumentOcr.Completion
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: DocumentOcr.Supervisor)
  end
end
