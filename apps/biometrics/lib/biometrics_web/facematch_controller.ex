defmodule BiometricsWeb.FacematchController do
  @moduledoc """
  `POST /v1/facematch` and `GET /v1/facematch/:id`.

  Creation stores both images and queues the comparison. With `prefer: wait=N` it answers
  `200` with the finished comparison when it ends within N seconds (capped by
  `max_wait_seconds`); otherwise `202` with `location`. A reused comparison answers `200`
  at once. Reads find only sessions of the caller's company.
  """
  use BiometricsWeb, :controller
  action_fallback(BiometricsWeb.FallbackController)
  alias Biometrics.Facematches
  alias BiometricsWeb.FacematchJSON
  alias BiometricsWeb.Schemas.FacematchParams

  plug(BiometricsWeb.ValidateParams,
    create: &FacematchParams.create/1,
    show: &FacematchParams.resource/1
  )

  def create(
        conn,
        %{"selfie_image" => selfie, "document_image" => document} = params
      ) do
    app = company(conn, params)

    attrs = %{
      app_id: app,
      external_id: params["external_id"] || Ecto.UUID.generate(),
      requested_external_id: params["external_id"],
      idempotency_key: List.first(get_req_header(conn, "idempotency-key"))
    }

    with true <- is_binary(app) and app != "",
         {:ok, %{session: session} = creation} <-
           Facematches.create_from_uploads(attrs, selfie, document) do
      created(conn, app, session, Map.get(creation, :reused, false))
    else
      false -> {:error, :invalid_request}
      error -> error
    end
  end

  def create(_conn, _), do: {:error, :invalid_request}

  def show(conn, %{"id" => id} = params) when is_binary(id),
    do: show_session(conn, Facematches.get(company(conn, params), id))

  def show(_conn, _), do: {:error, :invalid_request}
  defp show_session(_conn, nil), do: {:error, :not_found}
  defp show_session(conn, session), do: respond(conn, 200, session)
  defp created(conn, _app, session, true), do: respond(conn, 200, session)

  defp created(conn, app, session, false) do
    max = Application.get_env(:biometrics, :max_wait_seconds, 10)
    answer(conn, app, session, AikeHttp.Prefer.wait(conn, max))
  end

  defp answer(conn, app, session, nil), do: accepted(conn, app, session)

  defp answer(conn, app, session, seconds) do
    conn = put_resp_header(conn, "preference-applied", "wait=#{seconds}")

    case Biometrics.Completion.await(session.id, seconds * 1_000) do
      {:ok, _finished} -> respond(conn, 200, Facematches.get(app, session.id))
      :timeout -> accepted(conn, app, session)
    end
  end

  defp accepted(conn, app, session) do
    conn
    |> put_resp_header("location", "/v1/facematch/#{session.id}")
    |> respond(202, Facematches.get(app, session.id))
  end

  defp company(conn, params), do: conn.assigns[:company_id] || params["app_id"]

  defp respond(conn, status, session),
    do: conn |> put_status(status) |> json(FacematchJSON.data(session))
end
