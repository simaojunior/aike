defmodule DocumentClassifierWeb.Router do
  use DocumentClassifierWeb, :router

  pipeline :classification do
    plug(DocumentClassifierWeb.ServiceAccountAuth, scopes: ["classifier:write"])
  end

  scope "/v1" do
    pipe_through(:classification)
    post("/classifications", DocumentClassifierWeb.ClassificationController, :create)
  end
end
