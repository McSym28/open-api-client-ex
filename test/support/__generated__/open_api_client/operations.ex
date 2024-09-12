defmodule OpenAPIClient.Operations do
  @moduledoc """
  Provides API endpoints related to operations
  """

  @base_url "https://example.com"

  @doc """
  Test endpoint

  Test endpoint

  ## Arguments

    * `path_param`: ["path-param"] Path parameter
    * `required_header`: ["X-Required-Header"] Required header parameter
    * `required_new_param`: Required additional parameter

  ## Options

    * `date_query_with_default`: Date query parameter with default. Default value is `~D[2022-12-15]`
    * `datetime_query`: DateTime query parameter
    * `optional_query`: Optional query parameter
    * `x_enum_query`: ["X-Enum-Query"] Enum query parameter
    * `x_enum_query_with_default`: ["X-Enum-Query-With-Default"] Enum query parameter with default. Default value is `:enum_9`
    * `x_integer_non_standard_format_query`: ["X-Integer-Non-Standard-Format-Query"] Integer query parameter with NON-standard format
    * `x_integer_standard_format_query`: ["X-Integer-Standard-Format-Query"] Integer query parameter with standard format
    * `x_static_flag`: ["X-Static-Flag"] Static flag query parameter. Default value is `true`
    * `date_header_with_default`: ["X-Date-Header-With-Default"] Date header parameter with default. Default value is `~D[2024-01-23]`
    * `optional_header`: ["X-Optional-Header"] Optional header parameter. Default value obtained through a call to `Application.get_env(:open_api_client_ex, :required_header)`
    * `optional_header_new_param`: Optional additional header parameter
    * `optional_new_param`: Optional additional parameter
    * `optional_new_param_with_default`: Optional additional parameter. Default value is `"new_param_value"`
    * `base_url`: Request's base URL. Default value is taken from `@base_url`
    * `pipeline`: Operation pipeline for making a request. Default value obtained through a call to `OpenAPIClient.Utils.get_config(:test, :operation_pipeline)}
    * `client`: Module that implements `OpenAPIClient` behaviour. Default value obtained through a call to `OpenAPIClient.Utils.get_config(:test, :client, OpenAPIClient)`

  """
  @spec get_test(String.t(), String.t(), String.t(), [
          {:date_query_with_default, Date.t()}
          | {:datetime_query, DateTime.t()}
          | {:optional_query, String.t()}
          | {:x_enum_query, :enum_1 | :enum_2 | :enum_3 | String.t()}
          | {:x_enum_query_with_default, :enum_7 | :enum_8 | :enum_9 | String.t()}
          | {:x_integer_non_standard_format_query, integer}
          | {:x_integer_standard_format_query, integer}
          | {:x_static_flag, true | boolean}
          | {:date_header_with_default, Date.t()}
          | {:optional_header, String.t()}
          | {:optional_header_new_param, String.t()}
          | {:optional_new_param, String.t()}
          | {:optional_new_param_with_default, String.t()}
          | {:base_url, String.t() | URI.t()}
          | {:pipeline, OpenAPIClient.pipeline()}
        ]) :: {:ok, OpenAPIClient.TestSchema.t()} | {:error, OpenAPIClient.Error.t()}
  def get_test(path_param, required_header, required_new_param, opts \\ []) do
    pipeline = opts[:pipeline] || OpenAPIClient.Utils.get_config(:test, :operation_pipeline)
    base_url = opts[:base_url] || @base_url
    client = opts[:client] || OpenAPIClient.Utils.get_config(:test, :client, OpenAPIClient)

    client.operation(
      %OpenAPIClient.State{
        request_base_url: base_url,
        request_path: "/test/{path_param}",
        method: :get,
        request_parameter_types: [
          {{:path_param, :path}, {"path-param", {:string, :generic}}},
          {{:date_query_with_default, :query},
           {"date_query_with_default", {:string, :date}, ~D[2022-12-15]}},
          {{:datetime_query, :query}, {"datetime_query", {:string, :date_time}}},
          {{:optional_query, :query}, {"optional_query", {:string, :generic}}},
          {{:x_enum_query, :query},
           {"X-Enum-Query",
            {:enum, [{:enum_1, "ENUM_1"}, {:enum_2, "ENUM_2"}, {:enum_3, "ENUM_3"}, :not_strict]}}},
          {{:x_enum_query_with_default, :query},
           {"X-Enum-Query-With-Default",
            {:enum, [{:enum_7, "ENUM_7"}, {:enum_8, "ENUM_8"}, {:enum_9, "ENUM_9"}, :not_strict]},
            :enum_9}},
          {{:x_integer_non_standard_format_query, :query},
           {"X-Integer-Non-Standard-Format-Query", {:integer, "int69"}}},
          {{:x_integer_standard_format_query, :query},
           {"X-Integer-Standard-Format-Query", {:integer, :int32}}},
          {{:x_static_flag, :query}, {"X-Static-Flag", {:enum, [true, :not_strict]}, true}},
          {{:date_header_with_default, :header},
           {"X-Date-Header-With-Default", {:string, :date}, ~D[2024-01-23]}},
          {{:optional_header, :header},
           {"X-Optional-Header", {:string, :generic},
            fn -> Application.get_env(:open_api_client_ex, :required_header) end}},
          {{:optional_header_new_param, :custom},
           {"optional_header_new_param", {:string, :generic}}},
          {{:required_header, :header}, {"X-Required-Header", {:string, :generic}}},
          {{:optional_new_param, :custom}, {"optional_new_param", {:string, :generic}}},
          {{:optional_new_param_with_default, :custom},
           {"optional_new_param_with_default", {:string, :generic}, "new_param_value"}},
          {{:required_new_param, :custom}, {"required_new_param", {:string, :generic}}}
        ],
        response_types: [{200, [{"application/json", {OpenAPIClient.TestSchema, :t}}]}],
        function_args: [
          path_param: path_param,
          required_header: required_header,
          required_new_param: required_new_param
        ],
        function_call: {__MODULE__, :get_test},
        function_opts: opts,
        profile: :test
      },
      pipeline
    )
  end

  @doc """
  Test endpoint

  Test endpoint

  ## Arguments

    * `body`

  ## Options

    * `string_header`: ["X-String-Header"] String header parameter
    * `x_config_strict_enum_header`: ["X-Config-Strict-Enum-Header"] Enum header parameter that has it's "strcictness" set through config
    * `base_url`: Request's base URL. Default value is taken from `@base_url`
    * `pipeline`: Operation pipeline for making a request. Default value obtained through a call to `OpenAPIClient.Utils.get_config(:test, :operation_pipeline)}
    * `client`: Module that implements `OpenAPIClient` behaviour. Default value obtained through a call to `OpenAPIClient.Utils.get_config(:test, :client, OpenAPIClient)`

  """
  @spec set_test(OpenAPIClient.TestRequestSchema.t(), [
          {:string_header, String.t()}
          | {:x_config_strict_enum_header,
             :config_strict_enum_1 | :config_strict_enum_2 | :config_strict_enum_3}
          | {:base_url, String.t() | URI.t()}
          | {:pipeline, OpenAPIClient.pipeline()}
        ]) :: :ok | :error | {:error, OpenAPIClient.Error.t()}
  def set_test(body, opts \\ []) do
    pipeline = opts[:pipeline] || OpenAPIClient.Utils.get_config(:test, :operation_pipeline)
    base_url = opts[:base_url] || @base_url
    client = opts[:client] || OpenAPIClient.Utils.get_config(:test, :client, OpenAPIClient)

    client.operation(
      %OpenAPIClient.State{
        request_base_url: base_url,
        request_path: "/test",
        method: :post,
        request_parameter_types: [
          {{:string_header, :header}, {"X-String-Header", {:string, :generic}}},
          {{:x_config_strict_enum_header, :header},
           {"X-Config-Strict-Enum-Header",
            {:enum,
             config_strict_enum_1: "CONFIG_STRICT_ENUM_1",
             config_strict_enum_2: "CONFIG_STRICT_ENUM_2",
             config_strict_enum_3: "CONFIG_STRICT_ENUM_3"}}}
        ],
        request_types: [{"application/json", {OpenAPIClient.TestRequestSchema, :t}}],
        response_types: [{"2XX", :null}, {true, :null}, {400, :null}],
        function_args: [body: body],
        function_call: {__MODULE__, :set_test},
        function_opts: opts,
        profile: :test
      },
      pipeline
    )
  end
end
