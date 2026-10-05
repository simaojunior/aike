defmodule DocumentOcr.Application do
  use Application

  def start(_type, _args) do
    children = [
      DocumentOcr.Repo,
      DocumentOcrWeb.Endpoint,
      {Oban, Application.fetch_env!(:document_ocr, Oban)}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: DocumentOcr.Supervisor)
  end
end
