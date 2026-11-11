defmodule DocumentOcrWeb.DocumentJSONTest do
  use ExUnit.Case, async: true
  alias DocumentOcr.Documents.{Document, DocumentResult}
  alias DocumentOcrWeb.DocumentJSON

  test "groups fields, keeps required ones and rounds confidence to two decimals" do
    run_id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    document = %Document{
      id: Ecto.UUID.generate(),
      run_id: run_id,
      status: "requires_confirmation",
      document_type: "cnh",
      country: "BR",
      images: [],
      inserted_at: DateTime.add(now, -1_250, :millisecond),
      updated_at: now,
      result: %DocumentResult{
        run_id: run_id,
        data: %{
          "document" => %{"type" => "cnh", "country" => "BR", "side" => "single"},
          "fields" => %{
            "full_name" => %{
              "value" => "NARUTO UZUMAKI",
              "raw_value" => "NARUTO UZUMAKI",
              "confidence" => 0.91234,
              "status" => "accepted"
            },
            "category" => %{
              "value" => "AB",
              "raw_value" => "AB",
              "confidence" => 0.8695,
              "status" => "requires_confirmation"
            }
          }
        }
      }
    }

    body = document |> DocumentJSON.data() |> Jason.encode!() |> Jason.decode!()

    assert [%{"classification" => classification, "person" => person, "document" => fields}] =
             body["data"]

    assert classification["side"] == "front_and_back"
    assert person["name"]["confidence"] == 0.91

    assert fields["category"] == %{
             "confidence" => 0.87,
             "rawValue" => "AB",
             "status" => "requires_confirmation",
             "value" => "AB"
           }

    assert person["taxId"] == %{
             "confidence" => 0.0,
             "rawValue" => nil,
             "status" => "rejected",
             "value" => nil
           }

    assert body["metadata"]["processingTimeMs"] == 1_250
  end
end
