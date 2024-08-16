defmodule OpenAPIClient.Generator.TestRendererTest do
  use ExUnit.Case, async: true
  alias OpenAPIClient.Generator.TestRenderer

  @clauses [
    {:null, {:pipe, quote(do: is_nil())}},
    {:boolean, {:pipe, quote(do: is_boolean())}},
    {{:boolean, "custom"}, "boolean with custom format", {:pipe, quote(do: is_boolean())}},
    {:integer, {:pipe, quote(do: is_integer())}},
    {{:integer, :int64}, "integer with int64 format", {:pipe, quote(do: is_integer())}},
    {:number, {:pipe, quote(do: is_number())}},
    {{:number, :float}, "number with float format", {:pipe, quote(do: is_number())}},
    {{:string, :date}, "date",
     {:pattern_pipe, quote(do: %Date{}), quote(do: Date.from_iso8601!())}},
    {{:string, :time}, "time",
     {:pattern_pipe, quote(do: %Time{}), quote(do: Time.from_iso8601!())}},
    {{:string, :date_time}, "date_time",
     {:pattern_pipe, quote(do: {:ok, %DateTime{}, _}), quote(do: DateTime.from_iso8601())}},
    {{:string, :uri}, "uri", {:pattern_pipe, quote(do: %URI{}), quote(do: URI.parse())}},
    {{:string, :generic}, "string", {:pipe, quote(do: is_binary())}},
    {{:array, :number}, "array of numbers", {:pipe, quote(do: Enum.all?(&is_number/1))}},
    {{:array, {:string, :generic}}, "array of strings",
     {:pipe, quote(do: Enum.all?(&is_binary/1))}},
    {{:const, 1}, "const integer", {:pipe, quote(do: is_integer())}},
    {{:enum, [3, 5, 1]}, "enum with integer", {:pipe, quote(do: is_integer())}},
    {{:enum, [enum1: "ENUM1", enum2: "ENUM2"]}, "enum with aliases",
     {:pipe, quote(do: is_binary())}},
    {:map, {:pipe, quote(do: is_map())}},
    {:any, {:pipe, quote(do: is_map())}}
  ]

  setup_all do
    %{
      state: %OpenAPIClient.Generator.TestRenderer.State{
        implementation: TestRenderer,
        renderer_state: %OpenAPI.Renderer.State{}
      }
    }
  end

  describe "type_example/3" do
    @clauses
    |> Enum.map(fn
      {type, check} -> {type, to_string(type), check}
      {_type, _test_suffix, _check} = clause -> clause
    end)
    |> Enum.map(fn {type, test_suffix, check} ->
      check =
        case check do
          {:pattern_pipe, pattern, pipe} ->
            quote do:
                    assert(
                      unquote(pattern) =
                        unquote(Macro.var(:state, nil))
                        |> TestRenderer.type_example(unquote(type), [])
                        |> unquote(pipe)
                    )

          {:pipe, pipe} ->
            quote do:
                    assert(
                      unquote(Macro.var(:state, nil))
                      |> TestRenderer.type_example(unquote(type), [])
                      |> unquote(pipe)
                    )
        end

      test "generate example for #{test_suffix}", %{state: state} = _context do
        unquote(check)
      end
    end)
  end
end
