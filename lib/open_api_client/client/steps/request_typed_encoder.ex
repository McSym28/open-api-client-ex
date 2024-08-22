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
          request_parameters: parameters,
          request_parameter_types: parameter_types,
          assigns: %{private: private_assigns}
        } = operation,
        opts
      ) do
    typed_encoder =
      Keyword.get_lazy(opts, :typed_encoder, fn ->
        OpenAPIClient.Utils.get_config(
          operation,
          :typed_encoder,
          OpenAPIClient.Client.TypedEncoder
        )
      end)

    with {:ok, operation_new} <- encode_body(operation, typed_encoder) do
      passed_parameters =
        private_assigns
        |> Map.take([:__args__, :__opts__])
        |> Enum.map(fn {_key, values} -> values end)
        |> Enum.concat()
        |> Map.new()

      parameter_type_map =
        Map.new(parameter_types, fn
          {{name_atom, location}, {name, type}} ->
            {name_atom, {location, {name, type, nil}}}

          {{name_atom, location}, {name, type, default}} ->
            {name_atom, {location, {name, type, default}}}
        end)

      parameter_type_map
      |> Enum.reduce(passed_parameters, fn
        {name_atom, {_location, {_name, _type, default}}}, acc
        when is_function(default, 0) ->
          Map.put_new_lazy(acc, name_atom, default)

        {name_atom, {_location, {_name, _type, default}}}, acc when not is_nil(default) ->
          Map.put_new(acc, name_atom, default)

        _, acc ->
          acc
      end)
      |> Enum.reduce_while({:ok, parameters}, fn
        {name_atom, value}, {:ok, acc} ->
          parameter_type_map
          |> Map.fetch(name_atom)
          |> case do
            {:ok, {location, {name, type, _default}}} -> {:ok, {location, {name, type}}}
            :error -> :error
          end
          |> case do
            {:ok, {location, {name, type}}} ->
              case typed_encoder.encode(
                     value,
                     type,
                     [
                       {:parameter, location, name},
                       {operation.request_url, operation.request_method}
                     ],
                     typed_encoder
                   ) do
                {:ok, encoded_value} ->
                  acc_new = Map.put(acc, {name, location}, to_string(encoded_value))
                  {:cont, {:ok, acc_new}}

                {:error, _} = error ->
                  {:halt, error}
              end

            :error ->
              {:cont, {:ok, acc}}
          end

        _, {:ok, acc} ->
          {:cont, {:ok, acc}}
      end)
      |> case do
        {:ok, parameters_new} ->
          operation_new
          |> Operation.put_request_parameters(parameters_new)

        {:error, %Error{} = error} ->
          Operation.set_result(
            operation,
            {:error, %Error{error | operation: operation, step: __MODULE__}}
          )
      end
    end
  end

  defp encode_body(%Operation{request_body: nil} = operation, _typed_encoder),
    do: {:ok, operation}

  defp encode_body(%Operation{request_body: body} = operation, typed_encoder) do
    {content_type, type} = get_type(operation)

    case typed_encoder.encode(
           body,
           type,
           [{:request_body, content_type}, {operation.request_url, operation.request_method}],
           typed_encoder
         ) do
      {:ok, encoded_body} ->
        operation_new = %Operation{operation | request_body: encoded_body}
        {:ok, operation_new}

      {:error, %Error{} = error} ->
        Operation.set_result(
          operation,
          {:error, %Error{error | operation: operation, step: __MODULE__}}
        )
    end
  end

  defp get_type(%Operation{request_types: types} = operation) do
    case Operation.get_request_content_type(operation) do
      {:ok, content_type} -> List.keyfind(types, content_type, 0, {content_type, :unknown})
      {:error, _} -> {nil, :unknown}
    end
  end
end
