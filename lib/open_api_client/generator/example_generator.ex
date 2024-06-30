if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.ExampleGenerator do
    alias OpenAPI.Processor.Schema.Field
    alias OpenAPI.Processor.Operation.Param
    alias OpenAPIClient.Generator.Param, as: GeneratorParam
    alias OpenAPIClient.Generator.Schema, as: GeneratorSchema
    alias OpenAPIClient.Generator.Field, as: GeneratorField

    @type type ::
            OpenAPIClient.Schema.type()
            | reference()
            | GeneratorParam.t()
            | GeneratorSchema.t()
            | GeneratorField.t()
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
                path :: path(),
                caller_module :: module()
              ) ::
                term()

    @behaviour __MODULE__

    @doc """
    Generate example value for a specific type

    ## Examples

        iex> integer = #{__MODULE__}.generate(:integer, [], #{__MODULE__})
        iex> is_integer(integer)
        true
        iex> number = #{__MODULE__}.generate(:number, [], #{__MODULE__})
        iex> is_number(number)
        true
        iex> list = #{__MODULE__}.generate({:array, :boolean}, [], #{__MODULE__})
        iex> is_list(list)
        true
        iex> {:ok, date_time, _} = {:string, :date_time} |> #{__MODULE__}.generate([], #{__MODULE__}) |> DateTime.from_iso8601()
        iex> match?(%DateTime{}, date_time)
        true
        iex> string = #{__MODULE__}.generate({:string, :generic}, [], #{__MODULE__})
        iex> is_binary(string)
        true

    """
    @impl __MODULE__
    def generate(:null, _path, _caller_module), do: nil
    def generate(:boolean, _path, _caller_module), do: true
    def generate(:integer, _path, _caller_module), do: 1
    def generate(:number, _path, _caller_module), do: 1.0
    def generate({:string, :date}, _path, _caller_module), do: "2024-01-02"
    def generate({:string, :date_time}, _path, _caller_module), do: "2024-01-02T01:23:45Z"
    def generate({:string, :time}, _path, _caller_module), do: "01:23:45"
    def generate({:string, :uri}, _path, _caller_module), do: "http://example.com"
    def generate({:string, _}, _path, _caller_module), do: "string"

    def generate({:array, type}, path, caller_module),
      do: [caller_module.generate(type, [[0] | path], caller_module)]

    def generate({:const, value}, _path, _caller_module), do: value
    def generate({:enum, [{_atom, value} | _]}, _path, _caller_module), do: value
    def generate({:enum, [value | _]}, _path, _caller_module), do: value
    def generate(type, _path, _caller_module) when type in [:any, :map], do: %{"a" => "b"}
    def generate(%GeneratorField{examples: [value | _]}, _path, _caller_module), do: value

    def generate(
          %GeneratorField{field: %Field{type: {:array, {:enum, _}}}, enum_options: enum_options},
          path,
          caller_module
        ),
        do: caller_module.generate({:array, {:enum, enum_options}}, path, caller_module)

    def generate(
          %GeneratorField{field: %Field{type: {:enum, _}}, enum_options: enum_options},
          path,
          caller_module
        ),
        do: caller_module.generate({:enum, enum_options}, path, caller_module)

    def generate(%GeneratorField{field: %Field{type: type}}, path, caller_module),
      do: caller_module.generate(type, path, caller_module)

    def generate(%GeneratorSchema{fields: all_fields}, path, caller_module) do
      all_fields
      |> Enum.flat_map(fn
        %GeneratorField{field: nil} ->
          []

        %GeneratorField{old_name: name} = field ->
          [{name, caller_module.generate(field, [name | path], caller_module)}]
      end)
      |> Map.new()
    end

    def generate(schema_ref, path, caller_module) when is_reference(schema_ref) do
      [{_, schema}] = :ets.lookup(:schemas, schema_ref)
      caller_module.generate(schema, path, caller_module)
    end

    def generate(%GeneratorParam{param: %Param{value_type: type}}, path, caller_module),
      do: caller_module.generate(type, path, caller_module)
  end
end
