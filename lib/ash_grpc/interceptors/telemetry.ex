defmodule AshGrpc.Interceptors.Telemetry do
  @moduledoc """
  Server interceptor emitting `[:ash_grpc, :rpc, :start | :stop | :exception]`
  telemetry events around each RPC.

  Returns the dispatcher's tuple rather than raising for control flow, per the
  `GRPC.ServerInterceptor` v1.0.0 contract:
  `{:ok, stream} | {:ok, stream, reply} | {:error, RPCError}`.
  """
  @behaviour GRPC.ServerInterceptor

  @impl true
  def init(opts), do: opts

  @impl true
  def call(req, stream, next, _opts) do
    start = System.monotonic_time()
    meta = %{method: stream.method_name, service: stream.service_name}

    :telemetry.execute([:ash_grpc, :rpc, :start], %{system_time: System.system_time()}, meta)

    try do
      result = next.(req, stream)
      duration = System.monotonic_time() - start

      case result do
        {:error, %GRPC.RPCError{} = err} ->
          :telemetry.execute([:ash_grpc, :rpc, :exception], %{duration: duration},
            Map.merge(meta, %{kind: :error, status: err.status}))

        _ok ->
          :telemetry.execute([:ash_grpc, :rpc, :stop], %{duration: duration}, meta)
      end

      result
    rescue
      e ->
        :telemetry.execute([:ash_grpc, :rpc, :exception],
          %{duration: System.monotonic_time() - start},
          Map.merge(meta, %{kind: :error, reason: e}))

        reraise e, __STACKTRACE__
    end
  end
end
