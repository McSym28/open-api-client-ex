defmodule Mix.Tasks.Api.Gen.Proxy do
  @moduledoc """
  **Proxy** for [mix api.gen](https://hexdocs.pm/oapi_generator/Mix.Tasks.Api.Gen.html).
  Interface is the same.

  ## Changes:

  * Extracts callbacks and webhooks from `spec_files` and copies them as operation to `paths`

  ## Example

  ```shell
  mix api.gen.proxy default ../rest-api-description/spec.yaml
  ```
  """
  use Mix.Task

  @temp_filename_length 16

  @shortdoc "(PROXY) Generate code from an Open API description"
  @requirements ["app.start"]
  @impl Mix.Task
  def run([profile | spec_files]) do
    profile_atom = String.to_atom(profile)

    %OpenAPIClient.Generator.TestRenderer.State{
      implementation:
        OpenAPIClient.Utils.get_config(
          profile_atom,
          :test_renderer,
          OpenAPIClient.Generator.TestRenderer
        ),
      renderer_state: %OpenAPI.Renderer.State{
        files: %{},
        implementation:
          :oapi_generator
          |> Application.get_env(profile_atom)
          |> Keyword.get(:renderer, OpenAPI.Renderer),
        operations: [],
        profile: profile_atom,
        schemas: %{}
      }
    }
    |> OpenAPIClient.Generator.TestRenderer.clear_router_test_routes()

    spec_files_new = Enum.map(spec_files, &process_spec_file/1)

    result = OpenAPI.run(profile, spec_files_new)

    Enum.each(spec_files_new -- spec_files, &File.rm!/1)

    result
  end

  def run(_args) do
    Mix.shell().error("Usage: mix api.gen.proxy [profile] [paths/to/spec.yaml]")
  end

  defp process_spec_file(filename) do
    openapi_spec = parse_spec_file(filename)

    paths = Map.get(openapi_spec, "paths", %{})

    paths_new =
      Enum.reduce(paths, paths, fn
        {_url, %{"$ref" => _reference}}, paths ->
          paths

        {url, path_item}, acc ->
          Enum.reduce(path_item, acc, fn
            {method, %{"callbacks" => callbacks}}, acc ->
              process_callbacks(callbacks, %{__parent_url__: url, __parent_method__: method}, acc)

            _, acc ->
              acc
          end)
      end)

    paths_new =
      openapi_spec
      |> Map.fetch("components")
      |> case do
        {:ok, %{"callbacks" => callbacks}} -> process_callbacks(callbacks, %{}, paths_new)
        {:ok, _} -> paths_new
        :error -> paths_new
      end

    paths_new =
      openapi_spec
      |> Map.fetch("webhooks")
      |> case do
        {:ok, webhooks} -> process_webhooks(webhooks, paths_new)
        :error -> paths_new
      end

    if paths == paths_new do
      filename
    else
      tmp_dir = System.tmp_dir!()

      filename_new =
        @temp_filename_length
        |> :crypto.strong_rand_bytes()
        |> Base.url_encode64(padding: false)
        |> then(&Enum.join([&1, "json"], "."))
        |> then(&Path.join(tmp_dir, &1))

      openapi_spec
      |> Map.put("paths", paths_new)
      |> Jason.encode!(pretty: true)
      |> then(&File.write!(filename_new, &1))

      filename_new
    end
  end

  defp parse_spec_file(relative_filename) do
    filename = relative_filename |> Path.absname() |> Path.expand()

    if File.exists?(filename) do
      YamlElixir.read_from_file!(filename)
    else
      raise RuntimeError, "File #{relative_filename} not found (expanded as #{filename})"
    end
  end

  defp process_callbacks(callbacks, query, paths) do
    Enum.reduce(callbacks, paths, fn
      {_name, %{"$ref" => _reference}}, paths ->
        paths

      {event_name, callback}, paths ->
        Enum.reduce(callback, paths, fn
          {_url, %{"$ref" => _reference}}, paths ->
            paths

          {url, path_item}, paths ->
            url_new =
              url
              |> process_callback_url()
              |> case do
                "/" <> _rest = url -> url
                url -> "/" <> url
              end

            query_new =
              query
              |> Map.merge(%{__name__: event_name, __uuid__: generate_uuid()})
              |> URI.encode_query()

            url =
              URI.parse("/__callbacks__#{url_new}")
              |> struct!(query: query_new)
              |> URI.to_string()

            Map.put(paths, url, path_item)
        end)
    end)
  end

  defp process_webhooks(webhooks, paths) do
    Enum.reduce(webhooks, paths, fn
      {_name, %{"$ref" => _reference}}, paths ->
        paths

      {name, path_item}, paths ->
        query = URI.encode_query(__name__: name, __uuid__: generate_uuid())
        url = URI.new!("/__webhooks__") |> struct!(query: query) |> URI.to_string()
        Map.put(paths, url, path_item)
    end)
  end

  defp process_callback_url(url) do
    url
    |> String.replace(~r/\{\$([^\}]+)\}/, fn expression ->
      expression
      |> String.split(["{$", "}"])
      |> Enum.at(1)
      |> String.replace("#/", ".")
      |> then(&"{*#{&1}*}")
    end)
    |> URI.parse()
    |> struct!(scheme: nil, host: nil, port: 80)
    |> URI.to_string()
  end

  defp generate_uuid() do
    20
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
