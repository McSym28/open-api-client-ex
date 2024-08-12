defmodule OpenAPIClient.Operations do
  @moduledoc """
  Provides API endpoints related to operations
  """

  @base_url "https://example.com"

  @doc """
  Test endpoint

  Test endpoint

  ## Arguments

    * `required_header`: ["X-Required-Header"] Required header parameter

  ## Options

    * `date_query_with_default`: Date query parameter with default. Default value is `~D[2022-12-15]`
    * `datetime_query`: DateTime query parameter
    * `optional_query`: Optional query parameter
    * `x_integer_non_standard_format_query`: ["X-Integer-Non-Standard-Format-Query"] Integer query parameter with NON-standard format
    * `x_integer_standard_format_query`: ["X-Integer-Standard-Format-Query"] Integer query parameter with standard format
    * `x_static_flag`: ["X-Static-Flag"] Static flag query parameter. Default value is `true`
    * `date_header_with_default`: ["X-Date-Header-With-Default"] Date header parameter with default. Default value is `"2024-01-23"`
    * `optional_header`: ["X-Optional-Header"] Optional header parameter. Default value obtained through a call to `Application.get_env(:open_api_client_ex, :required_header)`
    * `base_url`: Request's base URL. Default value is taken from `@base_url`
    * `client_pipeline`: Client pipeline for making a request. Default value obtained through a call to `OpenAPIClient.Utils.get_config(__operation__, :client_pipeline)}

  """
  @spec get_test(String.t(), [
          {:date_query_with_default, Date.t()}
          | {:datetime_query, DateTime.t()}
          | {:optional_query, String.t()}
          | {:x_integer_non_standard_format_query, integer}
          | {:x_integer_standard_format_query, integer}
          | {:x_static_flag, true}
          | {:date_header_with_default, Date.t()}
          | {:optional_header, String.t()}
          | {:base_url, String.t() | URI.t()}
          | {:client_pipeline, OpenAPIClient.Client.pipeline()}
        ]) :: {:ok, OpenAPIClient.TestSchema.t()} | {:error, OpenAPIClient.Client.Error.t()}
  def get_test(required_header, opts \\ []) do
    client_pipeline = Keyword.get(opts, :client_pipeline)
    base_url = opts[:base_url] || @base_url

    typed_encoder =
      OpenAPIClient.Utils.get_config(:test, :typed_encoder, OpenAPIClient.Client.TypedEncoder)

    {:ok, date_query_with_default} =
      opts
      |> Keyword.get_lazy(:date_query_with_default, fn -> ~D[2022-12-15] end)
      |> typed_encoder.encode(
        {:string, :date},
        [{:parameter, :query, "date_query_with_default"}, {"/test", :get}],
        typed_encoder
      )

    x_static_flag = Keyword.get_lazy(opts, :x_static_flag, fn -> true end)

    {:ok, date_header_with_default} =
      opts
      |> Keyword.get_lazy(:date_header_with_default, fn -> "2024-01-23" end)
      |> typed_encoder.encode(
        {:string, :date},
        [{:parameter, :header, "X-Date-Header-With-Default"}, {"/test", :get}],
        typed_encoder
      )

    optional_header =
      Keyword.get_lazy(opts, :optional_header, fn ->
        Application.get_env(:open_api_client_ex, :required_header)
      end)

    query_params =
      opts
      |> Keyword.take([
        :datetime_query,
        :optional_query,
        :x_integer_non_standard_format_query,
        :x_integer_standard_format_query
      ])
      |> Enum.map(fn
        {:x_integer_standard_format_query, value} ->
          {"X-Integer-Standard-Format-Query", value}

        {:x_integer_non_standard_format_query, value} ->
          {:ok, value_new} =
            typed_encoder.encode(
              value,
              {:integer, "int69"},
              [{:parameter, :query, "X-Integer-Non-Standard-Format-Query"}, [{"/test", :get}]],
              typed_encoder
            )

          {"X-Integer-Non-Standard-Format-Query", value_new}

        {:optional_query, value} ->
          {"optional_query", value}

        {:datetime_query, value} ->
          {:ok, value_new} =
            typed_encoder.encode(
              value,
              {:string, :date_time},
              [{:parameter, :query, "datetime_query"}, [{"/test", :get}]],
              typed_encoder
            )

          {"datetime_query", value_new}
      end)
      |> Map.new()
      |> Map.merge(%{
        "date_query_with_default" => date_query_with_default,
        "X-Static-Flag" => x_static_flag
      })

    headers = %{
      "X-Date-Header-With-Default" => date_header_with_default,
      "X-Optional-Header" => optional_header,
      "X-Required-Header" => required_header
    }

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

    * `string_header`: ["X-String-Header"] String header parameter
    * `base_url`: Request's base URL. Default value is taken from `@base_url`
    * `client_pipeline`: Client pipeline for making a request. Default value obtained through a call to `OpenAPIClient.Utils.get_config(__operation__, :client_pipeline)}

  """
  @spec set_test(OpenAPIClient.TestRequestSchema.t(), [
          {:string_header, String.t()}
          | {:base_url, String.t() | URI.t()}
          | {:client_pipeline, OpenAPIClient.Client.pipeline()}
        ]) :: :ok | :error | {:error, OpenAPIClient.Client.Error.t()}
  def set_test(body, opts \\ []) do
    client_pipeline = Keyword.get(opts, :client_pipeline)
    base_url = opts[:base_url] || @base_url

    headers =
      opts
      |> Keyword.take([:string_header])
      |> Enum.map(fn {:string_header, value} -> {"X-String-Header", value} end)
      |> Map.new()

    %OpenAPIClient.Client.Operation{
      request_base_url: base_url,
      request_url: "/test",
      request_body: body,
      request_method: :post,
      request_headers: headers,
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
