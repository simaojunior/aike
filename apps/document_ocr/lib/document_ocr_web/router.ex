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
    post("/documents", DocumentOcrWeb.DocumentController, :create)
    post("/documents/:id/reprocess", DocumentOcrWeb.DocumentController, :reprocess)
    post("/documents/:id/cancel", DocumentOcrWeb.DocumentController, :cancel)
  end

  scope "/v1" do
    pipe_through(:ocr_read)
    get("/documents/:id", DocumentOcrWeb.DocumentController, :show)
  end
end
