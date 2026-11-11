defmodule Biometrics.FacematchTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Biometrics.Repo
  import Plug.Test

  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Biometrics.Repo)
    Sandbox.mode(Biometrics.Repo, {:shared, self()})
    :ok
  end

  test "multipart facematch stores both blobs and completes" do
    selfie_path = Path.join(System.tmp_dir!(), "selfie-#{System.unique_integer([:positive])}.jpg")

    document_path =
      Path.join(System.tmp_dir!(), "document-#{System.unique_integer([:positive])}.jpg")

    File.write!(selfie_path, "selfie")
    File.write!(document_path, "document")

    try do
      params = %{
        "app_id" => "konoha",
        "external_id" => "user-9876",
        "selfie_image" => %Plug.Upload{
          path: selfie_path,
          filename: "selfie.jpg",
          content_type: "image/jpeg"
        },
        "document_image" => %Plug.Upload{
          path: document_path,
          filename: "document.jpg",
          content_type: "image/jpeg"
        }
      }

      response = BiometricsWeb.FacematchController.create(conn(:post, "/v1/facematch"), params)
      assert response.status == 202
      accepted = Jason.decode!(response.resp_body)
      id = accepted["id"]
      assert Plug.Conn.get_resp_header(response, "location") == ["/v1/facematch/#{id}"]

      assert {accepted["version"], accepted["status"], accepted["error"], accepted["data"]} ==
               {"v1", "pending", nil, []}

      assert [
               %{"fieldname" => "selfieImage", "size" => 6, "mimetype" => "image/jpeg"},
               %{"fieldname" => "documentImage", "size" => 8}
             ] = accepted["metadata"]["filesInfo"]

      assert :ok = perform_job(Biometrics.Workers.CompareFaces, %{"id" => id})

      response =
        BiometricsWeb.FacematchController.show(conn(:get, "/v1/facematch/#{id}"), %{
          "id" => id,
          "app_id" => "konoha"
        })

      body = Jason.decode!(response.resp_body, objects: :ordered_objects)
      assert Enum.map(body.values, &elem(&1, 0)) == ~w(id version status error data metadata)
      body = Jason.decode!(response.resp_body)
      assert body["status"] == "completed"

      assert [%{"faceMatch" => face_match, "resources" => [selfie, document]}] = body["data"]
      assert face_match == %{"matched" => true, "similarity" => 0.98, "decision" => "approved"}
      assert {selfie["fieldname"], document["fieldname"]} == {"selfieImage", "documentImage"}

      assert is_integer(body["metadata"]["processingTimeMs"])

      other_reader = Plug.Conn.assign(conn(:get, "/v1/facematch/#{id}"), :company_id, "akatsuki")

      assert {:error, :not_found} =
               BiometricsWeb.FacematchController.show(other_reader, %{"id" => id})

      repeated = BiometricsWeb.FacematchController.create(conn(:post, "/v1/facematch"), params)
      assert repeated.status == 200
      assert Jason.decode!(repeated.resp_body)["id"] == id
      assert Jason.decode!(repeated.resp_body)["data"] == body["data"]
      assert Biometrics.Repo.aggregate(Biometrics.Facematches.FacematchSession, :count) == 1

      other_company = Plug.Conn.assign(conn(:post, "/v1/facematch"), :company_id, "akatsuki")
      fresh = BiometricsWeb.FacematchController.create(other_company, params)
      assert fresh.status == 202
      refute Jason.decode!(fresh.resp_body)["id"] == id
    after
      File.rm(selfie_path)
      File.rm(document_path)
    end
  end
end
