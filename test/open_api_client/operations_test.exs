defmodule OpenAPIClient.OperationsTest do
  use ExUnit.Case, async: true
  import Mox
  @httpoison OpenAPIClient.HTTPoisonMock
  setup do
    Mox.defmock(@httpoison, for: HTTPoison.Base)
    :ok
  end

  setup :verify_on_exit!

  describe("test/1") do
    test "[200] performs a request and encodes OpenAPIClient.TestSchema from response's body" do
      expect(@httpoison, :request, fn :get, "https://example.com/test", _, _, _ ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           headers: [{"Content-Type", "application/json"}],
           body:
             %{
               "Boolean" => true,
               "DateTime" => "2024-01-02T01:23:45Z",
               "Enum" => "ENUM_1",
               "Integer" => 1,
               "Number" => 1.0,
               "String" => "string"
             }
             |> Jason.encode!()
         }}
      end)

      assert {:ok,
              %OpenAPIClient.TestSchema{
                boolean: true,
                date_time: ~U[2024-01-02 01:23:45Z],
                enum: :enum_1,
                integer: 1,
                number: 1.0,
                string: "string"
              }} == OpenAPIClient.Operations.test(base_url: "https://example.com")
    end
  end
end
