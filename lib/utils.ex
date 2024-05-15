defmodule OpenAPIGenerator.Utils do
  @spec param_config(atom(), String.t() | URI.t(), String.t(), atom()) :: keyword()
  def param_config(profile, operation_url, name, location) do
    with profile_config when is_list(profile_config) <-
           Application.get_env(:open_api_generator_ex, profile),
         operations when is_list(operations) <- Keyword.get(profile_config, :operations),
         config when is_list(config) <-
           find_param_config(operations, operation_url, name, location) do
      config
    else
      _ -> []
    end
  end

  defp find_param_config(operations, operation_url, name, location) do
    Enum.reduce_while(operations, nil, fn {pattern, operation_config}, _ ->
      with true <- pattern_match?(operation_url, pattern),
           params <- operation_config[:params],
           {_, config} <- List.keyfind(params, {name, location}, 0) do
        {:halt, config}
      else
        _ -> {:cont, nil}
      end
    end)
  end

  defp pattern_match?(str, pattern) do
    case pattern do
      :all -> true
      %Regex{} = regex -> Regex.match?(regex, str)
      ^str -> true
      _ -> false
    end
  end
end
