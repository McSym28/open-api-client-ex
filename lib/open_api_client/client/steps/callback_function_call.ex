defmodule OpenAPIClient.Client.Steps.CallbackFunctionCall do
  @moduledoc """
  `Pluggable` step implementation for encoding `Operation.request_body` and `Operation.request_parameters` using types provided by the `oapi_generator` library

  Accepts the following `opts`:
  * `:typed_encoder` - Module that implements `OpenAPIClient.Client.TypedEncoder` behaviour. Default value obtained through a call to `OpenAPIClient.Utils.get_config(operation, :typed_encoder, OpenAPIClient.Client.TypedEncoder)`

  """

  @behaviour Pluggable

  alias OpenAPIClient.Client.{Error, Operation}

  @type options :: []

  @impl Pluggable
  @spec init(options()) :: options()
  def init(opts), do: opts

  @impl Pluggable
  @spec call(Operation.t(), options()) :: Operation.t()
  def call(
        %Operation{
          response_types: response_types,
          assigns: %{private: private_assigns}
        } = operation,
        _opts
      ) do
    # TODO: Try to process path params

    private_assigns
    |> Map.fetch(:__call__)
    |> case do
      {:ok, {module, function_name}} ->
        args =
          private_assigns
          |> Map.get(:__args__, [])
          |> Keyword.values()

        opts = Map.get(private_assigns, :__opts__, [])

        module
        |> apply(function_name, args ++ [opts])
        |> case do
          :ok -> {true, nil}
          {:ok, result} -> {true, result}
          :error -> {false, nil}
          {:error, result} -> {false, result}
        end
        |> case do
          {false, %Error{} = error} ->
            Operation.set_result(
              operation,
              {:error, %Error{error | operation: operation, step: __MODULE__}}
            )

          {is_result_success, result_body} ->
            {exact_responses, non_exact_responses} =
              Enum.split_with(response_types, fn {status_code, _} -> is_integer(status_code) end)

            non_exact_responses
            |> Enum.reduce(
              Enum.map(exact_responses, fn {status_code, types} ->
                {status_code, status_code, types}
              end),
              fn {status_code, types}, responses ->
                status_code_range =
                  case status_code do
                    <<digit::utf8, "XX">> ->
                      digit = digit - ?0
                      ((digit + 1) * 100 - 1)..(digit * 100)

                    true ->
                      299..200

                    false ->
                      599..400
                  end

                status_code_int =
                  Enum.find(status_code_range, fn code ->
                    not List.keymember?(responses, code, 0)
                  end)

                List.keystore(
                  responses,
                  status_code_int,
                  0,
                  {status_code_int, status_code, types}
                )
              end
            )
            |> Enum.sort_by(fn {status_code_int, _, _} -> status_code_int end)
            |> Enum.reduce_while(
              operation,
              fn {status_code_int, status_code, response_types}, operation ->
                is_success = status_code_int >= 200 and status_code_int < 300

                response_types
                |> case do
                  :null -> [{nil, :null}]
                  types -> types
                end
                |> Enum.find(fn
                  {_content_type, type} ->
                    is_result_success == is_success and result_type_match?(result_body, type)
                end)
                |> case do
                  {content_type, _type} ->
                    operation_new =
                      %Operation{
                        operation
                        | response_status_code: status_code_int,
                          response_body: result_body
                      }
                      |> then(fn operation ->
                        if content_type do
                          Operation.put_response_parameter(
                            operation,
                            "Content-Type",
                            :header,
                            content_type
                          )
                        else
                          operation
                        end
                      end)
                      |> Operation.put_private(:__status_code__, status_code)

                    {:halt, operation_new}

                  nil ->
                    {:cont, operation}
                end
              end
            )
        end

      :error ->
        Operation.set_result(
          operation,
          {:error,
           Error.new(
             message: "`:__call__` is not set",
             operation: operation,
             reason: :call_not_set,
             step: __MODULE__
           )}
        )
    end
  end

  defp result_type_match?(nil, :null), do: true
  defp result_type_match?(%struct{}, {struct, type}) when is_atom(type), do: true
  defp result_type_match?(map, :map) when is_map(map), do: true
  defp result_type_match?(_result, _type), do: false
end
