defmodule OpenAPIClient.Utils do
  @spec is_module?(atom()) :: boolean()
  def is_module?(atom) when is_atom(atom) do
    Code.ensure_loaded(atom)
    function_exported?(atom, :module_info, 1)
  end

  @spec does_implement_behaviour?(module(), atom()) :: boolean()
  def does_implement_behaviour?(module, behaviour) when is_atom(behaviour) do
    (module.module_info(:attributes) || [])
    |> Keyword.get(:behaviour, [])
    |> Enum.member?(behaviour)
  end
end
