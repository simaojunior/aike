defmodule Biometrics.FaceTestEngine do
  @behaviour Biometrics.Engine

  @resources [
    %{
      "fieldname" => "selfie_image",
      "page" => 0,
      "face" => %{
        "confidence" => 0.95,
        "bounding_box" => %{"top" => 0.21, "left" => 0.33, "width" => 0.3, "height" => 0.41}
      }
    },
    %{
      "fieldname" => "document_image",
      "page" => 0,
      "face" => %{
        "confidence" => 0.94,
        "bounding_box" => %{"top" => 0.46, "left" => 0.25, "width" => 0.14, "height" => 0.24}
      }
    }
  ]

  def compare("naruto-selfie", _document, _opts), do: {:ok, found(0.71234)}
  def compare("kakashi-selfie", _document, _opts), do: {:ok, found(0.41)}

  def compare("empty-selfie", _document, _opts) do
    {:ok,
     %{
       "match" => false,
       "similarity_score" => nil,
       "selfie_face_detected" => false,
       "document_face_detected" => true,
       "resources" => [],
       "faces" => %{"selfie_image" => 0, "document_image" => 1},
       "issues" => %{"selfie_image" => ["no_face"], "document_image" => []}
     }}
  end

  defp found(similarity) do
    %{
      "match" => true,
      "similarity_score" => similarity,
      "selfie_face_detected" => true,
      "document_face_detected" => true,
      "resources" => @resources,
      "faces" => %{"selfie_image" => 1, "document_image" => 1},
      "issues" => %{"selfie_image" => [], "document_image" => []}
    }
  end
end

defmodule Biometrics.FacematchEnvelopeTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Biometrics.Repo
  import Plug.Test
  import Plug.Conn

  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Biometrics.Repo)
    Sandbox.mode(Biometrics.Repo, {:shared, self()})
    keys = [:engine, :decision]
    original = Map.new(keys, &{&1, Application.get_env(:biometrics, &1)})
    Application.put_env(:biometrics, :engine, Biometrics.FaceTestEngine)
    Application.put_env(:biometrics, :decision, approve_at: 0.5, review_at: 0.363)

    directory = Path.join(System.tmp_dir!(), "konoha-faces-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)

    on_exit(fn ->
      for {key, value} <- original, do: Application.put_env(:biometrics, key, value)
      File.rm_rf!(directory)
    end)

    %{directory: directory}
  end

  defp upload(directory, name, bytes) do
    path = Path.join(directory, name)
    File.write!(path, bytes)
    %Plug.Upload{path: path, filename: name, content_type: "image/jpeg"}
  end

  defp request(directory, selfie, headers \\ []) do
    params = %{
      "appId" => "konoha",
      "externalId" => "naruto-#{System.unique_integer([:positive])}",
      "selfieImage" => upload(directory, "selfie.jpg", selfie),
      "documentImage" => upload(directory, "document.jpg", "konoha-document")
    }

    Enum.reduce(headers, conn(:post, "/v1/facematch", params), fn {key, value}, conn ->
      put_req_header(conn, key, value)
    end)
    |> BiometricsWeb.Endpoint.call([])
  end

  defp completed(directory, selfie) do
    accepted = request(directory, selfie)
    assert accepted.status == 202
    id = Jason.decode!(accepted.resp_body)["id"]
    assert :ok = perform_job(Biometrics.Workers.CompareFaces, %{"id" => id})

    conn(:get, "/v1/facematch/#{id}?appId=konoha")
    |> BiometricsWeb.Endpoint.call([])
    |> Map.fetch!(:resp_body)
    |> Jason.decode!()
  end

  test "a match returns the faces used, rounded similarity and the faces per file",
       %{directory: directory} do
    body = completed(directory, "naruto-selfie")
    assert body["status"] == "completed"
    assert [item] = body["data"]

    assert item["faceMatch"] == %{
             "matched" => true,
             "similarity" => 0.71,
             "decision" => "approved"
           }

    assert [
             %{"fieldname" => "selfieImage", "page" => 0, "face" => selfie_face},
             %{"fieldname" => "documentImage", "page" => 0}
           ] = item["resources"]

    assert selfie_face == %{
             "confidence" => 0.95,
             "boundingBox" => %{"top" => 0.21, "left" => 0.33, "width" => 0.3, "height" => 0.41}
           }

    assert [
             %{"fieldname" => "selfieImage", "faces" => 1, "issues" => []},
             %{"fieldname" => "documentImage", "faces" => 1, "issues" => []}
           ] = body["metadata"]["filesInfo"]
  end

  test "a similarity between the review and approval limits goes to manual review",
       %{directory: directory} do
    [item] = completed(directory, "kakashi-selfie")["data"]

    assert item["faceMatch"] == %{
             "matched" => true,
             "similarity" => 0.41,
             "decision" => "manual_review"
           }
  end

  test "without a face in one file there is no comparison, and the file says why",
       %{directory: directory} do
    body = completed(directory, "empty-selfie")
    assert {body["status"], body["error"], body["data"]} == {"completed", nil, []}

    assert [
             %{"fieldname" => "selfieImage", "faces" => 0, "issues" => ["no_face"]},
             %{"fieldname" => "documentImage", "faces" => 1, "issues" => []}
           ] = body["metadata"]["filesInfo"]
  end

  test "Prefer: wait answers 200 with the comparison when it finishes in time",
       %{directory: directory} do
    task = Task.async(fn -> request(directory, "naruto-selfie", [{"prefer", "wait=5"}]) end)

    Stream.repeatedly(fn ->
      Process.sleep(20)
      Oban.drain_queue(Biometrics.Oban, queue: :biometrics)
    end)
    |> Enum.find(&(&1.success > 0))

    response = Task.await(task, 10_000)
    assert response.status == 200
    assert get_resp_header(response, "preference-applied") == ["wait=5"]
    body = Jason.decode!(response.resp_body)
    assert body["status"] == "completed"
    assert [%{"faceMatch" => %{"decision" => "approved"}}] = body["data"]
  end

  test "input fields are camelCase; snake_case names are refused with the camelCase field",
       %{directory: directory} do
    params = %{
      "appId" => "konoha",
      "externalId" => "naruto-snake",
      "selfie_image" => upload(directory, "selfie.jpg", "naruto-selfie"),
      "document_image" => upload(directory, "document.jpg", "konoha-document")
    }

    response = conn(:post, "/v1/facematch", params) |> BiometricsWeb.Endpoint.call([])
    assert response.status == 422
    fields = Jason.decode!(response.resp_body)["errors"] |> Enum.map(& &1["field"]) |> Enum.sort()
    assert fields == ["documentImage", "selfieImage"]
  end

  test "externalId is optional; without it the service generates one",
       %{directory: directory} do
    params = %{
      "appId" => "konoha",
      "selfieImage" => upload(directory, "selfie.jpg", "naruto-selfie"),
      "documentImage" => upload(directory, "document.jpg", "konoha-document")
    }

    response = conn(:post, "/v1/facematch", params) |> BiometricsWeb.Endpoint.call([])
    assert response.status == 202
    id = Jason.decode!(response.resp_body)["id"]
    session = Biometrics.Repo.get!(Biometrics.Facematches.FacematchSession, id)
    assert {:ok, _} = Ecto.UUID.cast(session.external_id)
  end

  test "repeating a request without externalId under the same idempotency key returns the same session",
       %{directory: directory} do
    send_once = fn ->
      params = %{
        "appId" => "konoha",
        "selfieImage" => upload(directory, "selfie.jpg", "naruto-selfie"),
        "documentImage" => upload(directory, "document.jpg", "konoha-document")
      }

      conn(:post, "/v1/facematch", params)
      |> put_req_header("idempotency-key", "konoha-retry-1")
      |> BiometricsWeb.Endpoint.call([])
    end

    first = send_once.()
    second = send_once.()
    assert first.status == 202
    assert second.status in [200, 202]
    assert Jason.decode!(second.resp_body)["id"] == Jason.decode!(first.resp_body)["id"]
  end

  test "without Prefer the answer is 202 with Location at once", %{directory: directory} do
    response = request(directory, "naruto-selfie")
    assert response.status == 202
    assert get_resp_header(response, "preference-applied") == []
    [location] = get_resp_header(response, "location")
    assert location == "/v1/facematch/" <> Jason.decode!(response.resp_body)["id"]
  end
end
