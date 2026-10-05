defmodule KycCore.JsonKeyFormatterTest do
  use ExUnit.Case, async: true

  test "converts nested atom and string keys to camelCase" do
    assert KycCore.JsonKeyFormatter.format(%{
             "birth_date" => [%{"expire_at" => "2029-01-01"}],
             service_account_id: "svc"
           }) == %{
             "serviceAccountId" => "svc",
             "birthDate" => [%{"expireAt" => "2029-01-01"}]
           }
  end

  test "keeps scalar values unchanged" do
    assert KycCore.JsonKeyFormatter.format([nil, true, 1, "text"]) == [nil, true, 1, "text"]
  end
end
