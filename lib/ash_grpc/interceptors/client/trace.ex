defmodule AshGrpc.Interceptors.Client.Trace do
  @moduledoc """
  Client interceptor that injects W3C trace context into outbound headers and
  emits `[:ash_grpc, :client, :rpc]` telemetry with round-trip duration.

  v1.0.0 client signature: `call(stream, req, next, opts)`.
  """
  @behaviour GRPC.Client.Interceptor

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%GRPC.Client.Stream{} = stream, req, next, _opts) do
    headers = inject_trace_context()
    stream = if headers == %{}, do: stream, else: GRPC.Client.Stream.put_headers(stream, headers)

    start = System.monotonic_time()
    result = next.(stream, req)

    :telemetry.execute(
      [:ash_grpc, :client, :rpc],
      %{duration: System.monotonic_time() - start},
      %{method: rpc_name(stream), result: tag(result)}
    )

    result
  end

  defp inject_trace_context do
    if Code.ensure_loaded?(:otel_propagator_text_map) do
      :otel_propagator_text_map.inject([]) |> Map.new()
    else
      %{}
    end
  end

  defp rpc_name(%GRPC.Client.Stream{rpc: {name, _, _}}), do: name
  defp rpc_name(_), do: nil

  defp tag({:ok, _}), do: :ok
  defp tag({:error, _}), do: :error
  defp tag(_), do: :other
end
