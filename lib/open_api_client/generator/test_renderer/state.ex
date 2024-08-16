if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.TestRenderer.State do
    @type t :: %__MODULE__{
            implementation: module(),
            renderer_state: OpenAPI.Renderer.State.t()
          }

    defstruct [
      :implementation,
      :renderer_state
    ]
  end
end
