defmodule DocumentOcrWeb.Router do
  use DocumentOcrWeb, :router

  pipeline :ocr_write do
    plug(DocumentOcrWeb.ServiceAccountAuth, scopes: ["ocr:write"])
  end

  pipeline :ocr_read do
    plug(DocumentOcrWeb.ServiceAccountAuth, scopes: ["ocr:read"])
  end

  scope "/v1" do
    pipe_through(:ocr_write)
    post("/extractions", DocumentOcrWeb.DocumentController, :create)
    post("/extractions/:id/reprocess", DocumentOcrWeb.DocumentController, :reprocess)
    post("/extractions/:id/cancel", DocumentOcrWeb.DocumentController, :cancel)
    post("/webhook-endpoints", DocumentOcrWeb.WebhookEndpointController, :create)
    delete("/webhook-endpoints/:id", DocumentOcrWeb.WebhookEndpointController, :delete)
  end

  scope "/v1" do
    pipe_through(:ocr_read)
    get("/extractions/:id", DocumentOcrWeb.DocumentController, :show)
    get("/webhook-endpoints", DocumentOcrWeb.WebhookEndpointController, :index)
  end
end
