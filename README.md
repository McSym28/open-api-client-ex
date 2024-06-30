# OpenAPIClient

OpenAPI generator AND client. Based on/uses the great package [open-api-generator](https://github.com/aj-foster/open-api-generator) and inspired by [open-api-github](https://github.com/aj-foster/open-api-github) (both projects created by [
AJ Foster](https://github.com/aj-foster))

## Differences from [open-api-generator](https://github.com/aj-foster/open-api-generator):
- All generated identifiers (parameter/field names and enum options) have "Elixir's look-and-feel" (converted using [`Macro.underscore/1`](https://hexdocs.pm/elixir/Macro.html#underscore/1)) by default (custom renaming rules can be set through configuration). For example: `merchantPaymInfo` -> `merchant_paym_info`, `EXTRA_CHARGE` -> `extra_charge`
- Generated enum options can be configured as strict - not allowing other values. Feature disabled by default
- Required query and header parameters used as operation function arguments when no defaults were configured for them
- Added generation for handling parameters (path, query and header) with defaults
- Added docstring generation for path and header parameters. Docstring now has two blocks `## Arguments` for required parameters without defaults and `## Options` for all the other parameters
- Added `@enforce_keys` for required schema fields
- "Fixed" processing of `2XX` response status codes and provided a way to set "successiveness" for `default` response status codes
- Added client module and pipeline (based on [pluggable](https://hex.pm/packages/pluggable)) to use generated operation. At this point library provides only a naive pipeline implementation for [httpoison](https://hex.pm/packages/httpoison) HTTP client. Library users can implement their own use it as a default one. Additionally library provides a way to configure decoders and encoders for different `Content-Type`s
- Generated operation tests based on spec examples

## TODOs
- [ ] Add documentation
- [ ] Wait for [open-api-generator](https://github.com/aj-foster/open-api-generator)'s release with my changes and use [hex.pm's version](https://hex.pm/packages/oapi_generator)
- [ ] Publish package to [hex.pm](https://hex.pm/)
- [ ] Publish documentation to [hexdocs.pm](https://hexdocs.pm/)
