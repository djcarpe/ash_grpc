defmodule AshGrpc.Resource.Method do
  @moduledoc """
  A single RPC method mapping an Ash action to a gRPC method.
  """

  defstruct [
    :name,
    :action,
    :request,
    :response,
    :rpc_name,
    :server_stream,
    :client_stream,
    :get?,
    :load,
    :fields,
    :description,
    :__spark_metadata__
  ]

  @type t :: %__MODULE__{
          name: atom(),
          action: atom(),
          request: module() | nil,
          response: module() | nil,
          rpc_name: String.t() | nil,
          server_stream: boolean(),
          client_stream: boolean(),
          get?: boolean(),
          load: list(),
          fields: list(atom()) | nil,
          description: String.t() | nil
        }
end
