defmodule OpenAPIClient.Client.Steps.RequestTypedEncoder do
  @moduledoc """
  `Pluggable` step implementation for encoding `Operation.request_body` and `Operation.request_parameters` using types provided by the `oapi_generator` library

  Accepts the following `opts`:
  * `:typed_encoder` - Module that implements `OpenAPIClient.Client.TypedEncoder` behaviour. Default value obtained through a call to `OpenAPIClient.Utils.get_config(operation, :typed_encoder, OpenAPIClient.Client.TypedEncoder)`

  """

  @behaviour Pluggable

  alias OpenAPIClient.Client.{Error, Operation}

  @type option :: [{:typed_encoder, module()}]
  @type options :: [option()]

  @impl Pluggable
  @spec init(options()) :: options()
  def init(opts), do: opts

  @impl Pluggable
  @spec call(Operation.t(), options()) :: Operation.t()
  def call(
        %Operation{
          request_url: request_url,
          request_method: request_method,
          request_parameter_types: parameter_types,
          assigns: %{private: private_assigns}
        } = operation,
        opts
      ) do
    parameter_type_map =
      Map.new(parameter_types, fn
        {{name_atom, location}, {name, type}} ->
          {name_atom, {location, name, type, nil}}

        {{name_atom, location}, {name, type, default}} ->
          {name_atom, {location, name, type, default}}
      end)

    passed_parameters =
      private_assigns
      |> Map.take([:__args__, :__opts__])
      |> Enum.map(fn {_key, values} -> values end)
      |> Enum.concat()
      |> Map.new()

    typed_encoder =
      Keyword.get_lazy(opts, :typed_encoder, fn ->
        OpenAPIClient.Utils.get_config(
          operation,
          :typed_encoder,
          OpenAPIClient.Client.TypedEncoder
        )
      end)

    path_rest = [{request_url, request_method}]

    parameter_type_map
    |> Enum.reduce(passed_parameters, fn
      {name_atom, {_location, _name, _type, default}}, acc
      when is_function(default, 0) ->
        Map.put_new_lazy(acc, name_atom, default)

      {name_atom, {_location, _name, _type, default}}, acc when not is_nil(default) ->
        Map.put_new(acc, name_atom, default)

      _, acc ->
        acc
    end)
    |> Enum.flat_map(fn {name_atom, value} ->
      parameter_type_map
      |> Map.fetch(name_atom)
      |> case do
        {:ok, {location, name, type, _default}} ->
          [{{:parameter, location, name}, type, value}]

        :error ->
          []
      end
    end)
    |> then(fn parameters ->
      case operation do
        %Operation{request_body: nil} ->
          parameters

        %Operation{request_body: body} ->
          {content_type, type} = get_request_type(operation)
          [{{:request_body, content_type}, type, body} | parameters]
      end
    end)
    |> Enum.reduce_while(operation, fn {path_prefix, type, value}, operation ->
      case typed_encoder.encode(
             value,
             type,
             [path_prefix | path_rest],
             typed_encoder
           ) do
        {:ok, encoded_value} ->
          operation_new =
            case path_prefix do
              {:request_body, _content_type} ->
                %Operation{operation | request_body: encoded_value}

              {:parameter, :path = location, name} ->
                parameter_type_map
                |> Enum.reduce_while(
                  operation,
                  fn
                    {name_atom, {^location, ^name, _type, _default}},
                    %Operation{request_url: request_url} = operation ->
                      request_url_new =
                        String.replace(request_url, "{#{name_atom}}", to_string(encoded_value))

                      operation_new = %Operation{operation | request_url: request_url_new}
                      {:halt, operation_new}

                    _, operation ->
                      {:cont, operation}
                  end
                )
                |> Operation.put_request_parameter(
                  name,
                  location,
                  to_string(encoded_value)
                )

              {:parameter, location, name} ->
                Operation.put_request_parameter(
                  operation,
                  name,
                  location,
                  to_string(encoded_value)
                )
            end

          {:cont, operation_new}

        {:error, %Error{} = error} ->
          Operation.set_result(
            operation,
            {:error, %Error{error | operation: operation, step: __MODULE__}}
          )
      end
    end)
  end

  defp get_request_type(%Operation{request_types: types} = operation) do
    case Operation.get_request_content_type(operation) do
      {:ok, content_type} -> List.keyfind(types, content_type, 0, {content_type, :unknown})
      {:error, _} -> {nil, :unknown}
    end
  end
end
