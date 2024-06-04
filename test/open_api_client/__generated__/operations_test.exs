defmodule OpenAPIClient.OperationsTest do
  use ExUnit.Case, async: true
  import Mox

  @httpoison OpenAPIClient.HTTPoisonMock

  setup :verify_on_exit!

  describe "test/1" do
    test "[200] performs a request and encodes OpenAPIClient.TestSchema from response's body" do
      expect(@httpoison, :request, fn :get, "https://example.com/test", _, _, _ ->
        assert {:ok, body_encoded} =
                 Jason.encode(%{
                   "Boolean" => true,
                   "DateTime" => "2024-01-02T01:23:45Z",
                   "Enum" => "ENUM_1",
                   "Integer" => 1,
                   "Number" => 1.0,
                   "String" => "string"
                 })

        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           headers: [{"Content-Type", "application/json"}],
           body: body_encoded
         }}
      end)

      assert {:ok,
              %OpenAPIClient.TestSchema{
                boolean: true,
                date_time: ~U[2024-01-02 01:23:45Z],
                enum: :enum1,
                integer: 1,
                number: 1.0,
                string: "string"
              }} == OpenAPIClient.Operations.test(base_url: "https://example.com")
    end
  end
end
