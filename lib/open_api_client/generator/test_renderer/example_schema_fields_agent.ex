defmodule OpenAPIClient.Generator.TestRenderer.ExampleSchemaFieldsAgent do
  use Agent
  alias OpenAPIClient.Generator.Schema, as: GeneratorSchema

  @spec start_link() :: Agent.on_start()
  def start_link() do
    Agent.start_link(fn -> {nil, []} end)
  end

  @spec update(Agent.agent(), reference()) :: :ok
  def update(pid, ref) do
    Agent.update(pid, fn
      {^ref, _} = state ->
        state

      _ ->
        [{_, %GeneratorSchema{schema_fields: schema_fields}}] = :ets.lookup(:schemas, ref)
        {ref, schema_fields}
    end)
  end

  @spec get(Agent.agent()) :: keyword(OpenAPIClient.Schema.schema_type())
  def get(pid), do: Agent.get(pid, fn {_ref, schema_fields} -> schema_fields end)
end
