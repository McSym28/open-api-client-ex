defmodule OpenAPIClient.Client.Error do
  @moduledoc """
  Exception struct used for communicating errors from the client

  This error covers errors generated by the client (for example, HTTP connection errors).

  ## Fields

    * `code` (integer): Status code of the API response, if a response was received.

    * `message` (string): Human-readable message describing the error. Defaults to a generic
      `"Unknown Error"`.

    * `operation` (`t:Operation.t/0`): Operation at the time of the error.

    * `reason` (atom): Easily-matched atom for common errors, like `:not_found`. Defaults to a
      generic `:error`. See **Error Reasons** below for a list of possible values.

    * `source` (term): Cause of the error. This could be an operation, an API error response, or
      something else.

    * `stacktrace` (`t:Exception.stacktrace/0`): Stacktrace from the time of the error. Defaults
      to a stack that terminates with the calling function, but can be overridden (for example,
      if a `__STACKTRACE__` is available in a `rescue` block).

    * `step` (`t:Client.step()/0`): Client's step active at the time of the error.

  Users of the library can match on the information in the `code` and `source` fields to extract
  additional information.

  Taken from [GitHub REST API Client for Elixir library](https://github.com/aj-foster/open-api-github)

  """

  alias OpenAPIClient.Client.Operation

  @typedoc "Client error"
  @type t :: %__MODULE__{
          code: integer | nil,
          message: String.t(),
          operation: Operation.t(),
          reason: atom(),
          source: term(),
          stacktrace: Exception.stacktrace(),
          step: OpenAPIClient.Client.step() | nil
        }

  @derive {Inspect, except: [:operation, :stacktrace]}
  defexception [:code, :message, :operation, :reason, :source, :stacktrace, :step]

  @doc """
  Create a new error struct with the given fields

  The current stacktrace is automatically filled in to the resulting error. Callers should specify
  the status `code` (if available), a `message`, the original `operation`, the `source` of the
  error, and which `step` or plugin is currently active.
  """
  @spec new(keyword) :: t
  def new(opts) do
    {:current_stacktrace, stack} = Process.info(self(), :current_stacktrace)
    # Drop `Process.info/2` and `new/1`.
    stacktrace = Enum.drop(stack, 2)

    fields =
      Keyword.merge(
        [
          message: "Unknown Error",
          reason: :error,
          stacktrace: stacktrace
        ],
        opts
      )

    struct!(%__MODULE__{}, fields)
  end
end
