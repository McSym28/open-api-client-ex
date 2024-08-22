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

    @impl Pluggable
    @spec init(options()) :: options()
    def init(opts), do: opts

    @impl Pluggable
    @spec call(Operation.t(), options()) :: Operation.t()
    def call(
          %Operation{
            request_body: body,
            request_method: method,
            request_parameters: parameters,
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

      {headers, query_params} =
        Enum.reduce(parameters, {%{}, %{}}, fn
          {{name, :header}, value}, {headers, query_params} ->
            headers_new = Map.put(headers, name, value)
            {headers_new, query_params}

          {{name, :query}, value}, {headers, query_params} ->
            query_params_new = Map.put(query_params, name, value)
            {headers, query_params_new}

          _, {headers, query_params} ->
            {headers, query_params}
        end)

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
          headers_new = Enum.map(headers, fn {key, value} -> {{key, :header}, value} end)

          %Operation{operation | response_body: body, response_status_code: status_code}
          |> Operation.put_response_parameters(headers_new)

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
