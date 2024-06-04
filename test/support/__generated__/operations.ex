defmodule OpenAPIClient.Operations do
  @moduledoc """
  Provides API endpoints related to operations
  """

  @base_url "https://example.com"

  @doc """
  Test endpoint

  Test endpoint

  ## Arguments

    * `required_header`: ["X-Required-Header"]
    * `optional_query`
    * `optional_header`: ["X-Optional-Header"]. Default value obtained through a call to `Application.get_env(:open_api_client_ex, :required_header)`
    * `base_url`: Request's base URL. Default value is taken from `@base_url`
    * `client_pipeline`: Client pipeline for making a request. Default value obtained through a call to `OpenAPIClient.Utils.get_config(__operation__, :client_pipeline)}

  """
  @spec get_test(String.t(), [
          {:optional_query, String.t()}
          | {:optional_header, String.t()}
          | {:base_url, String.t() | URI.t()}
          | {:client_pipeline, OpenAPIClient.Client.pipeline()}
        ]) :: {:ok, OpenAPIClient.TestSchema.t()} | {:error, OpenAPIClient.Client.Error.t()}
  def get_test(required_header, opts \\ []) do
    client_pipeline = Keyword.get(opts, :client_pipeline)
    base_url = opts[:base_url] || @base_url

    optional_header =
      Keyword.get_lazy(opts, :optional_header, fn ->
        Application.get_env(:open_api_client_ex, :required_header)
      end)

    query_params =
      opts
      |> Keyword.take([:optional_query])
      |> Enum.map(fn {:optional_query, value} -> {"optional_query", value} end)
      |> Map.new()

    headers = %{"X-Optional-Header" => optional_header, "X-Required-Header" => required_header}

    %OpenAPIClient.Client.Operation{
      request_base_url: base_url,
      request_url: "/test",
      request_method: :get,
      request_headers: headers,
      request_query_params: query_params,
      response_types: [{200, [{"application/json", {OpenAPIClient.TestSchema, :t}}]}]
    }
    |> OpenAPIClient.Client.Operation.put_private(
      __info__: {__MODULE__, :get_test, required_header: required_header},
      __opts__: opts,
      __profile__: :test
    )
    |> OpenAPIClient.Client.perform(client_pipeline)
  end

  @doc """
  Test endpoint

  Test endpoint

  ## Arguments

    * `body`

  ## Options

    * `base_url`: Request's base URL. Default value is taken from `@base_url`
    * `client_pipeline`: Client pipeline for making a request. Default value obtained through a call to `OpenAPIClient.Utils.get_config(__operation__, :client_pipeline)}

  """
  @spec set_test(OpenAPIClient.TestRequestSchema.t(), [
          {:base_url, String.t() | URI.t()} | {:client_pipeline, OpenAPIClient.Client.pipeline()}
        ]) :: :ok | :error | {:error, OpenAPIClient.Client.Error.t()}
  def set_test(body, opts \\ []) do
    client_pipeline = Keyword.get(opts, :client_pipeline)
    base_url = opts[:base_url] || @base_url

    %OpenAPIClient.Client.Operation{
      request_base_url: base_url,
      request_url: "/test",
      request_body: body,
      request_method: :post,
      request_types: [{"application/json", {OpenAPIClient.TestRequestSchema, :t}}],
      response_types: [{"2XX", :null}, {:default, :null}, {400, :null}]
    }
    |> OpenAPIClient.Client.Operation.put_private(
      __info__: {__MODULE__, :set_test, body: body},
      __opts__: opts,
      __profile__: :test
    )
    |> OpenAPIClient.Client.perform(client_pipeline)
  end
end
