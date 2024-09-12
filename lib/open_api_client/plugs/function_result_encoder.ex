defmodule OpenAPIClient.Plugs.FunctionResultEncoder do
  @moduledoc """
  A plug for encoding the function call's result.
  """

  @behaviour Plug

  alias OpenAPIClient.Error

  @impl Plug
  @spec init(opts :: Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(conn, _opts) do
    %OpenAPIClient.State{result: result, response_types: response_types} =
      state = OpenAPIClient.get_state(conn)

    result
    |> case do
      :ok -> {true, nil}
      {:ok, result} -> {true, result}
      :error -> {false, nil}
      {:error, result} -> {false, result}
    end
    |> case do
      {false, %Error{} = error} ->
        OpenAPIClient.set_state_result(
          conn,
          {:error, %Error{error | conn: conn, plug: __MODULE__}}
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
          conn,
          fn {status_code_int, status_code, response_types}, conn ->
            is_success = status_code_int >= 200 and status_code_int < 300

            response_types
            |> case do
              :null -> [{nil, :null}]
              types -> types
            end
            |> Enum.find(fn
              {_content_type, type} ->
                is_result_success == is_success and response_type_match?(result_body, type)
            end)
            |> case do
              {content_type, _type} ->
                state_new = %OpenAPIClient.State{
                  state
                  | response_status_code: status_code,
                    response_body: result_body
                }

                conn_new =
                  conn
                  |> OpenAPIClient.set_state(state_new)
                  |> then(fn conn ->
                    if content_type do
                      Plug.Conn.put_resp_header(conn, "content-type", content_type)
                    else
                      conn
                    end
                  end)
                  |> Plug.Conn.put_status(status_code_int)

                {:halt, conn_new}

              nil ->
                {:cont, conn}
            end
          end
        )
    end
  end

  defp response_type_match?(nil, :null), do: true
  defp response_type_match?(%struct{}, {struct, type}) when is_atom(type), do: true
  defp response_type_match?(map, :map) when is_map(map), do: true
  defp response_type_match?(_result, _type), do: false
end
