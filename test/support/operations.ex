defmodule OpenAPIClient.Operations do
  @moduledoc """
  Provides API endpoint related to operations
  """

  @base_url "https://example.com"

  @doc """
  Test endpoint

  Test endpoint

  ## Options

    * `base_url`: Request's base URL. Default value is taken from `@base_url`
    * `client_pipeline`: Client pipeline for making a request. Default value obtained through a call to `OpenAPIClient.Utils.get_config(:default, :client_pipeline)}

  """
  @spec test([
          {:base_url, String.t() | URI.t()} | {:client_pipeline, OpenAPIClient.Client.pipeline()}
        ]) :: {:ok, OpenAPIClient.TestSchema.t()} | {:error, OpenAPIClient.Client.Error.t()}
  def test opts \\ [] do
    client_pipeline =
      Keyword.get_lazy(opts, :client_pipeline, fn ->
        OpenAPIClient.Utils.get_config(:default, :client_pipeline)
      end)

    base_url = opts[:base_url] || @base_url

    %OpenAPIClient.Client.Operation{
      request_base_url: base_url,
      request_url: "/test",
      request_method: :get,
      response_types: [{200, [{"application/json", {OpenAPIClient.TestSchema, :t}}]}]
    }
    |> OpenAPIClient.Client.Operation.put_private(
      __info__: {__MODULE__, :test, []},
      __profile__: :default,
      __opts__: opts
    )
    |> OpenAPIClient.Client.perform(client_pipeline)
  end
end
