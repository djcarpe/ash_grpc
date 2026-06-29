defmodule AshGrpc.Interceptors.Context do
  @moduledoc """
  Server interceptor that resolves an Ash actor and tenant from request
  headers and stashes them in `stream.local` for the dispatcher to read.

  Configure the resolver functions:

      intercept AshGrpc.Interceptors.Context,
        actor: {MyApp.Auth, :actor_from_token},
        tenant: {MyApp.Tenancy, :from_headers}

  Each MFA receives the headers map and returns the actor/tenant (or nil).
  """
  @behaviour GRPC.ServerInterceptor

  @impl true
  def init(opts), do: opts

  @impl true
  # Server side: call(req, stream, next, opts)
  def call(req, stream, next, opts) do
    headers = GRPC.Stream.get_headers(stream) || %{}

    actor = resolve(opts[:actor], headers)
    tenant = resolve(opts[:tenant], headers)

    local =
      stream
      |> Map.get(:local, %{})
      |> Kernel.||(%{})
      |> Map.put(:actor, actor)
      |> Map.put(:tenant, tenant)

    next.(req, %{stream | local: local})
  end

  defp resolve(nil, _headers), do: nil
  defp resolve({mod, fun}, headers), do: apply(mod, fun, [headers])
  defp resolve(fun, headers) when is_function(fun, 1), do: fun.(headers)
end
