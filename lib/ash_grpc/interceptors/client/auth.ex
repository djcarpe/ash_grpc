defmodule AshGrpc.Interceptors.Client.Auth do
  @moduledoc """
  Client interceptor injecting a bearer token into outbound request headers.

  Note the v1.0.0 client signature differs from the server: `call/4` is
  `(stream, req, next, opts)` and `next` is `(stream, req -> rpc_return)`.

  Configure per-connection:

      GRPC.Stub.connect(target,
        interceptors: [{AshGrpc.Interceptors.Client.Auth, token: "..."}]
      )

  or rely on the process dictionary key `:ash_grpc_token`.
  """
  @behaviour GRPC.Client.Interceptor

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%GRPC.Client.Stream{} = stream, req, next, opts) do
    token = opts[:token] || Process.get(:ash_grpc_token)

    stream =
      case token do
        nil -> stream
        t -> GRPC.Client.Stream.put_headers(stream, %{"authorization" => "Bearer #{t}"})
      end

    next.(stream, req)
  end
end
