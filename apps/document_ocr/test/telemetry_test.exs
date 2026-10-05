defmodule DocumentOcr.TelemetryTest do
  use ExUnit.Case, async: true

  test "emits duration and stage outcome without sensitive fields" do
    ref = make_ref()

    handler = fn event, measurements, metadata, _config ->
      send(self(), {ref, event, measurements, metadata})
    end

    :telemetry.attach(ref, [:aike, :document, :stage], handler, nil)

    document = %{id: "document-id", app_id: "acme"}
    assert :ok = DocumentOcr.Telemetry.execute(:ocr, document, fn -> :ok end)

    assert_receive {^ref, [:aike, :document, :stage], %{duration: duration},
                    %{stage: :ocr, outcome: :ok}}

    assert is_integer(duration)
    :telemetry.detach(ref)
  end
end
