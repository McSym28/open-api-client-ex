defmodule OpenAPIClient.OperationsTest do
  use ExUnit.Case, async: true
  alias OpenAPIClient.Operations
  alias OpenAPIClient.TestSchema
  import Mox

  @httpoison OpenAPIClient.HTTPoisonMock

  setup :verify_on_exit!

  describe "test/1" do
    test "successfully performs a requests" do
      expect(@httpoison, :request, fn :get, "https://example.com/test", _, [], _ ->
        {:ok,
         %HTTPoison.Response{
           body:
             %{
               "Boolean" => false,
               "Integer" => 1,
               "Number" => 1.0,
               "String" => "string",
               "DateTime" => "2024-01-02T01:23:45Z",
               "Enum" => "ENUM_1",
               "Extra" => "some_data"
             }
             |> Jason.encode!(),
           headers: [{"Content-Type", "application/json"}],
           status_code: 200
         }}
      end)

      assert {:ok,
              %TestSchema{
                boolean: false,
                integer: 1,
                number: 1.0,
                string: "string",
                date_time: ~U[2024-01-02T01:23:45Z],
                enum: :enum_1
              }} == Operations.test()
    end
  end
end
