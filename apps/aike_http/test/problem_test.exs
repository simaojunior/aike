defmodule AikeHttp.ProblemTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  test "Peri validation exposes only field/detail and uses the exact problem contract" do
    {:error, errors} =
      Peri.validate(%{"password" => {:required, :string}}, %{
        "password" => %{secret: "DO-NOT-LEAK"}
      })

    response =
      conn(:post, "/")
      |> put_resp_header("x-request-id", "request-123")
      |> AikeHttp.Problem.validation(errors)

    assert response.status == 422

    assert get_resp_header(response, "content-type") == [
             "application/problem+json; charset=utf-8"
           ]

    assert get_resp_header(response, "x-request-id") == ["request-123"]

    assert Jason.decode!(response.resp_body) == %{
             "code" => "validation",
             "detail" => "One or more request fields are invalid.",
             "errors" => [%{"field" => "password", "detail" => "This field has an invalid type."}]
           }

    assert response.resp_body ==
             ~s({"code":"validation","detail":"One or more request fields are invalid.","errors":[{"field":"password","detail":"This field has an invalid type."}]})

    refute response.resp_body =~ "DO-NOT-LEAK"
  end

  test "domain and unexpected failures omit field errors" do
    assert Jason.encode!(AikeHttp.Problem.from_template("500.json")) ==
             ~s({"code":"internal_server_error","detail":"Internal server error."})

    response = AikeHttp.Problem.send(conn(:get, "/"), 409, "idempotency_conflict")
    assert response.status == 409
    assert Map.keys(Jason.decode!(response.resp_body)) |> Enum.sort() == ["code", "detail"]
  end

  test "native Peri length and missing errors do not lose field paths" do
    {:error, errors} =
      Peri.validate(
        %{"name" => {:required, {:string, [min: 2]}}, "email" => {:required, :string}},
        %{"name" => "a"}
      )

    assert AikeHttp.FieldIssues.from_peri(errors) == [
             %{field: "email", detail: "This field is required."},
             %{field: "name", detail: "Must contain at least 2 characters."}
           ]
  end

  test "invalid idempotency headers fail before the payload validator" do
    for headers <- [[String.duplicate("x", 257)], ["first", "second"], [""]] do
      request = conn(:post, "/") |> put_private(:phoenix_action, :create)
      request = %{request | req_headers: Enum.map(headers, &{"idempotency-key", &1})}

      response =
        AikeHttp.ValidateParams.call(request, %{
          create: fn _ -> flunk("payload validation ran") end
        })

      assert response.halted
      assert response.status == 422
      assert [%{"field" => "idempotency-key"}] = Jason.decode!(response.resp_body)["errors"]
    end
  end
end
