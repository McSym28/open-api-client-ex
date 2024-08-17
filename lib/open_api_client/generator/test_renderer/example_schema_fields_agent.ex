defmodule OpenAPIClient.Generator.TestRenderer.ExampleSchemaFieldsAgent do
  use Agent
  alias OpenAPIClient.Generator.Schema, as: GeneratorSchema
  alias OpenAPI.Processor.Schema

  @spec start_link() :: Agent.on_start()
  def start_link() do
    Agent.start_link(fn -> nil end)
  end

  @spec update(Agent.agent(), GeneratorSchema.t()) :: :ok
  def update(pid, %GeneratorSchema{schema: %Schema{ref: schema_ref}} = generator_schema) do
    Agent.update(pid, fn
      %GeneratorSchema{schema: %Schema{ref: ^schema_ref}} = state -> state
      _ -> generator_schema
    end)
  end

  @spec get(Agent.agent()) :: GeneratorSchema.t()
  def get(pid), do: Agent.get(pid, & &1)
end
