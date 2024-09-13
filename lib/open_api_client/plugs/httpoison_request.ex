if Code.ensure_loaded?(HTTPoison) do
  defmodule OpenAPIClient.Plugs.HTTPoisonRequest do
    @moduledoc """
    A plug for making an HTTP request through `HTTPoison`.

    ## Options:
    * `:httpoison` - `HTTPoison` module. Default value obtained through a call to `OpenAPIClient.Utils.get_config(conn, :httpoison, HTTPoison)`.
    * `:headers` - Default `HTTPoison.request/5` `:headers`.
    * `:query_params` - Default `HTTPoison.request/5` query params (passed through `[:options, :params]`).
    * `:cookies` - Default `HTTPoison.request/5` cookies (passed as `"Cookie"` headers).
    * `:options` - Default `HTTPoison.request/5` `:options`.

    """

    @behaviour Plug

    alias OpenAPIClient.Error

    @type option ::
            {:httpoison, module()}
            | {:headers, %{String.t() => String.t()} | [{String.t(), String.t()}]}
            | {:query_params, %{String.t() => String.t()} | [{String.t(), String.t()}]}
            | {:cookies, %{String.t() => String.t()} | [{String.t(), String.t()}]}
            | {:options, keyword()}
    @type options :: [option()]

    @impl Plug
    @spec init(options()) :: options()
    def init(opts), do: opts

    @impl Plug
    @spec call(Plug.Conn.t(), options()) :: Plug.Conn.t()
    def call(%Plug.Conn{req_headers: headers} = conn, opts) do
      httpoison =
        Keyword.get_lazy(opts, :httpoison, fn ->
          OpenAPIClient.Utils.get_config(conn, :httpoison, HTTPoison)
        end)

      url = Plug.Conn.request_url(conn)

      %Plug.Conn{query_params: query_params, req_cookies: cookies} =
        conn =
        conn
        |> Plug.Conn.fetch_query_params()
        |> Plug.Conn.fetch_cookies()

      body =
        conn
        |> OpenAPIClient.get_state()
        |> case do
          %OpenAPIClient.State{request_body: request_body} -> request_body
          nil -> nil
        end

      cookies =
        opts
        |> Keyword.get(:cookies, [])
        |> Enum.to_list()
        |> Kernel.++(Enum.to_list(cookies))

      headers =
        opts
        |> Keyword.get(:headers, [])
        |> Enum.to_list()
        |> Kernel.++(headers)

      params =
        opts
        |> Keyword.get(:query_params, [])
        |> Map.new()
        |> Map.merge(query_params)
        |> Map.to_list()

      options =
        opts
        |> Keyword.get(:options, [])
        |> Keyword.update(:params, params, &OpenAPIClient.Utils.config_merge(&1, params))
        |> Keyword.update(:hackney, [cookie: cookies], &Keyword.merge(&1, cookie: cookies))

      conn
      |> OpenAPIClient.State.parse_method()
      |> httpoison.request(url, body || "", headers, options)
      |> case do
        {:ok,
         %HTTPoison.Response{body: body, headers: headers, status_code: status_code} = _response} ->
          headers
          |> Enum.reduce(conn, fn {key, value}, conn ->
            Plug.Conn.put_resp_header(conn, String.downcase(key), value)
          end)
          |> Plug.Conn.resp(status_code, body || "")

        {:error, %HTTPoison.Error{} = error} ->
          OpenAPIClient.set_state_result(
            conn,
            {:error,
             Error.new(
               message: "Error during HTTP request",
               conn: conn,
               reason: :http_response_failed,
               source: error,
               plug: __MODULE__
             )}
          )
      end
    end
  end
end
