defmodule OpenAPIClient.Client.Steps.RequestTypedDecoder do
  @moduledoc """
  `Pluggable` step implementation for decoding `Operation.request_body` and `Operation.request_parameters` using types provided by the `oapi_generator` library

  Accepts the following `opts`:
  * `:typed_decoder` - Module that implements `OpenAPIClient.Client.TypedDecoder` behaviour. Default value obtained through a call to `OpenAPIClient.Utils.get_config(operation, :typed_decoder, OpenAPIClient.Client.TypedDecoder)`

  """

  @behaviour Pluggable

  alias OpenAPIClient.Client.{Error, Operation}

  @type option :: [{:typed_decoder, module()}]
  @type options :: [option()]

  @impl Pluggable
  @spec init(options()) :: options()
  def init(opts), do: opts

  @impl Pluggable
  @spec call(Operation.t(), options()) :: Operation.t()
  def call(
        %Operation{
          request_path: request_path,
          request_method: request_method,
          request_parameters: request_parameters,
          request_parameter_types: parameter_types,
          request_parameter_args: parameter_args
        } = operation,
        opts
      ) do
    parameter_type_map =
      parameter_types
      |> Enum.map(fn
        {{name_atom, location}, {name, type}} ->
          {name, {location, name_atom, type, nil}}

        {{name_atom, location}, {name, type, default}} ->
          {name, {location, name_atom, type, default}}
      end)
      |> Enum.map(fn
        {name, {:header = _location, _name_atom, _type, _default} = value} ->
          {String.downcase(name), value}

        {name, value} ->
          {name, value}
      end)
      |> Map.new()

    typed_decoder =
      Keyword.get_lazy(opts, :typed_decoder, fn ->
        OpenAPIClient.Utils.get_config(
          operation,
          :typed_decoder,
          OpenAPIClient.Client.TypedDecoder
        )
      end)

    path_rest = [{request_path, request_method}]

    request_parameters
    |> Enum.flat_map(fn {{name, _location}, value} ->
      parameter_type_map
      |> Map.fetch(name)
      |> case do
        {:ok, {location, _name_atom, type, _default}} ->
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
    |> Enum.reduce_while({operation, %{}}, fn {path_prefix, type, value},
                                              {operation, parameters} ->
      value
      |> typed_decoder.decode(type, [path_prefix | path_rest], typed_decoder)
      |> case do
        {:ok, decoded_value} ->
          case path_prefix do
            {:request_body, _content_type} ->
              operation_new = %Operation{operation | request_body: decoded_value}
              {:cont, {operation_new, parameters}}

            {:parameter, _location, name} ->
              parameters_new = Map.put(parameters, name, decoded_value)
              {:cont, {operation, parameters_new}}
          end

        {:error, %Error{} = error} ->
          operation_new =
            Operation.set_result(
              operation,
              {:error, %Error{error | operation: operation, step: __MODULE__}}
            )

          {:halt, {operation_new, parameters}}
      end
    end)
    |> case do
      {%Operation{halted: true} = operations_new, _parameters} ->
        operations_new

      {operations_new, parameters} ->
        {args, opts} =
          parameter_type_map
          |> Enum.flat_map(fn {name, {_location, name_atom, _type, default}} ->
            parameters
            |> Map.fetch(name)
            |> case do
              {:ok, value} ->
                [{name_atom, value}]

              :error ->
                cond do
                  is_function(default, 0) -> [{name_atom, default.()}]
                  not is_nil(default) -> [{name_atom, default}]
                  :else -> []
                end
            end
          end)
          |> Keyword.split(parameter_args)

        parameter_args_indexed = Enum.with_index(parameter_args)

        args_sorted =
          parameter_args
          |> Enum.map(&{&1, nil})
          |> Keyword.merge(args)
          |> Enum.sort_by(fn {name_atom, _value} ->
            Keyword.fetch!(parameter_args_indexed, name_atom)
          end)

        args_new =
          case operations_new do
            %Operation{request_types: []} -> args_sorted
            %Operation{request_body: request_body} -> args_sorted ++ [body: request_body]
          end

        Operation.put_private(operations_new, __args__: args_new, __opts__: opts)
    end
  end

  defp get_request_type(%Operation{request_types: types} = operation) do
    case Operation.get_request_content_type(operation) do
      {:ok, content_type} -> List.keyfind(types, content_type, 0, {content_type, :unknown})
      {:error, _} -> {nil, :unknown}
    end
  end
end
