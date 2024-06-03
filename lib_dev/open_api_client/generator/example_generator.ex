defmodule OpenAPIClient.Generator.ExampleGenerator do
  alias OpenAPI.Processor.Schema.Field
  alias OpenAPI.Processor.Operation.Param
  alias OpenAPIClient.Generator.Param, as: GeneratorParam
  alias OpenAPIClient.Generator.Schema, as: GeneratorSchema
  alias OpenAPIClient.Generator.Field, as: GeneratorField

  @type type ::
          OpenAPIClient.Schema.type()
          | reference()
          | %GeneratorParam{}
          | %GeneratorSchema{}
          | %GeneratorField{}
  @type path ::
          list(
            String.t()
            | nonempty_list(non_neg_integer())
            | {:parameters, String.t()}
            | {:request_body, OpenAPIClient.Client.Operation.content_type()}
            | {:response_body, OpenAPIClient.Client.Operation.response_status_code(),
               OpenAPIClient.Client.Operation.content_type()}
            | {OpenAPIClient.Client.Operation.url(), OpenAPIClient.Client.Operation.method()}
          )

  @callback generate(
              type :: type(),
              state :: OpenAPI.Renderer.State.t(),
              path :: path(),
              caller_module :: module()
            ) ::
              term()

  @behaviour __MODULE__

  @impl __MODULE__
  def generate(:null, _state, _path, _caller_module), do: nil
  def generate(:boolean, _state, _path, _caller_module), do: true
  def generate(:integer, _state, _path, _caller_module), do: 1
  def generate(:number, _state, _path, _caller_module), do: 1.0
  def generate({:string, :date}, _state, _path, _caller_module), do: "2024-01-02"
  def generate({:string, :date_time}, _state, _path, _caller_module), do: "2024-01-02T01:23:45Z"
  def generate({:string, :time}, _state, _path, _caller_module), do: "01:23:45"
  def generate({:string, :uri}, _state, _path, _caller_module), do: "http://example.com"
  def generate({:string, _}, _state, _path, _caller_module), do: "string"

  def generate({:array, type}, state, path, caller_module),
    do: [caller_module.generate(type, state, [[0] | path], caller_module)]

  def generate({:const, value}, _state, _path, _caller_module), do: value
  def generate({:enum, [{_atom, value} | _]}, _state, _path, _caller_module), do: value
  def generate({:enum, [value | _]}, _state, _path, _caller_module), do: value
  def generate(type, _state, _path, _caller_module) when type in [:any, :map], do: %{"a" => "b"}
  def generate(%GeneratorField{examples: [value | _]}, _state, _path, _caller_module), do: value

  def generate(
        %GeneratorField{field: %Field{type: {:array, {:enum, _}}}, enum_options: enum_options},
        state,
        path,
        caller_module
      ),
      do: caller_module.generate({:array, {:enum, enum_options}}, state, path, caller_module)

  def generate(
        %GeneratorField{field: %Field{type: {:enum, _}}, enum_options: enum_options},
        state,
        path,
        caller_module
      ),
      do: caller_module.generate({:enum, enum_options}, state, path, caller_module)

  def generate(%GeneratorField{field: %Field{type: type}}, state, path, caller_module),
    do: caller_module.generate(type, state, path, caller_module)

  def generate(%GeneratorSchema{fields: all_fields}, state, path, caller_module) do
    all_fields
    |> Enum.flat_map(fn
      %GeneratorField{field: nil} ->
        []

      %GeneratorField{old_name: name} = field ->
        [{name, caller_module.generate(field, state, [name | path], caller_module)}]
    end)
    |> Map.new()
  end

  def generate(schema_ref, state, path, caller_module) when is_reference(schema_ref) do
    [{_, schema}] = :ets.lookup(:schemas, schema_ref)
    caller_module.generate(schema, state, path, caller_module)
  end

  def generate(%GeneratorParam{param: %Param{value_type: type}}, state, path, caller_module),
    do: caller_module.generate(type, state, path, caller_module)
end
