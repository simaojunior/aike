defmodule AikeObservabilityTest do
  use ExUnit.Case, async: true

  alias AikeObservability, as: Observability

  test "classifies HTTP statuses like the Kuatia logger" do
    assert Observability.status_class(200) == :success
    assert Observability.status_class(404) == :client_error
    assert Observability.status_class(503) == :server_error
  end

  test "maps status classes to structured log levels" do
    assert Observability.log_level(200) == :info
    assert Observability.log_level(422) == :warning
    assert Observability.log_level(500) == :error
  end

  test "redacts sensitive fields recursively" do
    assert Observability.redact(%{
             cpf: "12345678900",
             nested: %{secret: "hidden", safe: "value"}
           }) == %{
             cpf: "[REDACTED]",
             nested: %{secret: "[REDACTED]", safe: "value"}
           }
  end
end
