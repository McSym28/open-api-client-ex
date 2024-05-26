if Code.ensure_loaded?(HTTPoison) do
  defmodule OpenAPIClient.Client.Steps.HTTPoisonClient do
    @moduledoc """
    `Pluggable` step implementation for making a HTTP request through `HTTPoison`

    Accepts the following `opts`:
    * `:httpoison` - `HTTPoison` module. Default value obtained through a call to `OpenAPIClient.Utils.get_config(operation, :httpoison, HTTPoison)`
    * `:headers` - Default `HTTPoison.request/5` `:headers`
    * `:query_params` - Default `HTTPoison.request/5` query params (passed through `[:options, :params]`)
    * `:options` - Default `HTTPoison.request/5` `:options`

    """

    @behaviour Pluggable

    alias OpenAPIClient.Client.{Error, Operation}

    @type option ::
            {:httpoison, module()}
            | {:headers, %{String.t() => String.t()} | [{String.t(), String.t()}]}
            | {:query_params, %{String.t() => String.t()} | [{String.t(), String.t()}]}
            | {:options, keyword()}
    @type options :: [option()]

    @impl true
    @spec init(options()) :: options()
    def init(opts), do: opts

    @impl true
    @spec call(Operation.t(), options()) :: Operation.t()
    def call(
          %Operation{
            request_body: body,
            request_headers: headers,
            request_method: method,
            request_query_params: query_params,
            request_base_url: base_url,
            request_url: url
          } = operation,
          opts
        ) do
      httpoison =
        Keyword.get_lazy(opts, :httpoison, fn ->
          OpenAPIClient.Utils.get_config(operation, :httpoison, HTTPoison)
        end)

      url = base_url |> URI.merge(url) |> URI.to_string()
      body = body || ""

      headers =
        opts
        |> Keyword.get(:headers, [])
        |> Map.new()
        |> Map.merge(headers)
        |> Map.to_list()

      params =
        opts
        |> Keyword.get(:query_params, [])
        |> Map.new()
        |> Map.merge(query_params)
        |> Map.to_list()

      options =
        opts
        |> Keyword.get(:options, [])
        |> Keyword.update(:params, params, &Keyword.merge(&1, params))

      case httpoison.request(method, url, body, headers, options) do
        {:ok,
         %HTTPoison.Response{body: body, headers: headers, status_code: status_code} = _response} ->
          %Operation{operation | response_body: body, response_status_code: status_code}
          |> Operation.put_response_headers(headers)

        {:error, %HTTPoison.Error{} = error} ->
          Operation.set_result(
            operation,
            {:error,
             Error.new(
               message: "Error during HTTP request",
               operation: operation,
               reason: :http_response_failed,
               source: error,
               step: __MODULE__
             )}
          )
      end
    end
  end
end
