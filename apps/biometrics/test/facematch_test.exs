defmodule Biometrics.FacematchTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Biometrics.Repo
  import Plug.Test

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Biometrics.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Biometrics.Repo, {:shared, self()})
    :ok
  end

  test "multipart facematch stores both blobs and completes" do
    selfie_path = Path.join(System.tmp_dir!(), "selfie-#{System.unique_integer([:positive])}.jpg")
    document_path = Path.join(System.tmp_dir!(), "document-#{System.unique_integer([:positive])}.jpg")
    File.write!(selfie_path, "selfie")
    File.write!(document_path, "document")

    try do
      params = %{
        "app_id" => "acme",
        "external_id" => "user-9876",
        "selfie_image" => %Plug.Upload{path: selfie_path, filename: "selfie.jpg", content_type: "image/jpeg"},
        "document_image" => %Plug.Upload{path: document_path, filename: "document.jpg", content_type: "image/jpeg"}
      }

      response = BiometricsWeb.FacematchController.create(conn(:post, "/v1/facematch"), params)
      assert response.status == 202
      id = Jason.decode!(response.resp_body)["id"]

      assert :ok = perform_job(Biometrics.Workers.CompareFaces, %{"id" => id})
      response = BiometricsWeb.FacematchController.show(conn(:get, "/v1/facematch/#{id}"), %{"id" => id})
      body = Jason.decode!(response.resp_body)
      assert body["status"] == "completed"
      assert body["result"]["match"]
      assert body["result"]["similarityScore"] == 0.98
    after
      File.rm(selfie_path)
      File.rm(document_path)
    end
  end
end
