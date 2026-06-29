defmodule AshGrpc.Server.Dispatcher do
  @moduledoc """
  Runs the Ash action mapped to a gRPC method and encodes the result.

  Supports unary read/create/update/destroy/generic actions, server-streaming
  reads (emitting one response per record via `GRPC.Server.send_reply/2`), and
  client-streaming creates (collecting the inbound stream then running a bulk
  action).

  The actor and tenant are read from `stream.local`, where the interceptors
  in `AshGrpc.Interceptors.*` stash them.
  """

  require Logger
  alias AshGrpc.{Codec, Resource.Info}

  @doc """
  Entry point invoked by the generated `GRPC.Server` callbacks.

  `request` is a decoded message for unary/server-streaming, or an
  `Enumerable` of messages for client-streaming.
  """
  def dispatch(resource, method_name, request, stream) do
    method = Info.method(resource, method_name)
    action = Ash.Resource.Info.action(resource, method.action)
    ctx = context(stream)

    cond do
      method.server_stream ->
        stream_read(resource, method, action, request, stream, ctx)

      method.client_stream ->
        client_stream(resource, method, action, request, ctx)

      true ->
        unary(resource, method, action, request, ctx)
    end
  end

  # ---- unary ----------------------------------------------------------------

  defp unary(resource, method, %{type: :read} = action, request, ctx) do
    input = Codec.decode_request(request)

    if method.get? do
      # For get? reads the request contains PK fields as a filter, not action inputs.
      # Use Ash.get so the PK lookup bypasses the action's accepted-input validation.
      pkey = Ash.Resource.Info.primary_key(resource)
      identity = Map.take(input, pkey)

      case Ash.get(resource, identity, actor: ctx.actor, tenant: ctx.tenant) do
        {:ok, nil} -> {:error, not_found()}
        {:ok, record} -> {:ok, Codec.encode_response(method.response, record)}
        {:error, error} -> {:error, to_rpc_error(error)}
      end
    else
      query =
        resource
        |> Ash.Query.for_read(action.name, input, actor: ctx.actor, tenant: ctx.tenant)
        |> Ash.Query.load(method.load)

      case Ash.read(query) do
        {:ok, records} -> {:ok, Codec.encode_response(method.response, records)}
        {:error, error} -> {:error, to_rpc_error(error)}
      end
    end
  end

  defp unary(resource, method, %{type: :create} = action, request, ctx) do
    input = Codec.decode_request(request)

    resource
    |> Ash.Changeset.for_create(action.name, input, actor: ctx.actor, tenant: ctx.tenant)
    |> Ash.create(load: method.load)
    |> encode_or_error(method)
  end

  defp unary(resource, method, %{type: :update} = action, request, ctx) do
    input = Codec.decode_request(request)
    # Strip PK fields: fetch uses them for lookup; for_update only accepts action inputs.
    pkey = Ash.Resource.Info.primary_key(resource)
    action_input = Map.drop(input, pkey)

    with {:ok, record} <- fetch(resource, input, ctx) do
      record
      |> Ash.Changeset.for_update(action.name, action_input, actor: ctx.actor, tenant: ctx.tenant)
      |> Ash.update(load: method.load)
      |> encode_or_error(method)
    end
  end

  defp unary(resource, method, %{type: :destroy} = action, request, ctx) do
    input = Codec.decode_request(request)
    # Strip PK fields before destroy changeset; they are used only for the fetch.
    pkey = Ash.Resource.Info.primary_key(resource)
    action_input = Map.drop(input, pkey)

    with {:ok, record} <- fetch(resource, input, ctx) do
      record
      |> Ash.Changeset.for_destroy(action.name, action_input, actor: ctx.actor, tenant: ctx.tenant)
      |> Ash.destroy(return_destroyed?: true)
      |> case do
        :ok -> {:ok, Codec.encode_response(method.response, record)}
        {:ok, destroyed} -> {:ok, Codec.encode_response(method.response, destroyed)}
        {:error, error} -> {:error, to_rpc_error(error)}
      end
    end
  end

  defp unary(resource, method, %{type: :action} = action, request, ctx) do
    input = Codec.decode_request(request)

    resource
    |> Ash.ActionInput.for_action(action.name, input, actor: ctx.actor, tenant: ctx.tenant)
    |> Ash.run_action()
    |> case do
      {:ok, result} -> {:ok, Codec.encode_response(method.response, result)}
      :ok -> {:ok, struct(method.response)}
      {:error, error} -> {:error, to_rpc_error(error)}
    end
  end

  # ---- server streaming -----------------------------------------------------

  defp stream_read(resource, method, action, request, stream, ctx) do
    input = Codec.decode_request(request)

    query =
      resource
      |> Ash.Query.for_read(action.name, input, actor: ctx.actor, tenant: ctx.tenant)
      |> Ash.Query.load(method.load)

    # Stream results without materializing the whole set where the data layer
    # supports it; Ash.stream!/2 paginates under the hood.
    try do
      query
      |> Ash.stream!()
      |> Stream.each(fn record ->
        GRPC.Server.send_reply(stream, Codec.encode_response(method.response, record))
      end)
      |> Stream.run()

      {:ok, stream}
    rescue
      e -> {:error, to_rpc_error(e)}
    end
  end

  # ---- client streaming -----------------------------------------------------

  defp client_stream(resource, method, %{type: :create} = action, request_enum, ctx) do
    inputs = Enum.map(request_enum, &Codec.decode_request/1)

    inputs
    |> Ash.bulk_create(resource, action.name,
      actor: ctx.actor,
      tenant: ctx.tenant,
      return_records?: true,
      return_errors?: true
    )
    |> case do
      %Ash.BulkResult{status: :success, records: records} ->
        {:ok, Codec.encode_response(method.response, records)}

      %Ash.BulkResult{errors: errors} ->
        {:error, to_rpc_error(errors)}
    end
  end

  defp client_stream(resource, method, action, request_enum, ctx) do
    # Fallback: run the action once per inbound message, reply with the last.
    request_enum
    |> Enum.reduce({:ok, nil}, fn req, _acc ->
      unary(resource, method, action, req, ctx)
    end)
  end

  # ---- helpers --------------------------------------------------------------

  defp fetch(resource, input, ctx) do
    pkey = Ash.Resource.Info.primary_key(resource)
    identity = Map.take(input, pkey)

    case Ash.get(resource, identity, actor: ctx.actor, tenant: ctx.tenant) do
      {:ok, record} -> {:ok, record}
      {:error, error} -> {:error, to_rpc_error(error)}
    end
  end

  defp encode_or_error({:ok, record}, method),
    do: {:ok, Codec.encode_response(method.response, record)}

  defp encode_or_error({:error, error}, _method), do: {:error, to_rpc_error(error)}

  defp context(stream) do
    local = Map.get(stream, :local) || %{}
    %{actor: Map.get(local, :actor), tenant: Map.get(local, :tenant)}
  end

  defp not_found do
    %GRPC.RPCError{status: GRPC.Status.not_found(), message: "not found"}
  end

  defp to_rpc_error(%GRPC.RPCError{} = e), do: e

  defp to_rpc_error(error) do
    class = Ash.Error.to_class(error)

    # Ash.Error.to_class wraps leaf errors in class-level structs (e.g. NotFound
    # inside Invalid), so check the errors list before matching the class type.
    has_not_found? = fn errors ->
      Enum.any?(List.wrap(errors), &is_struct(&1, Ash.Error.Query.NotFound))
    end

    status =
      cond do
        is_struct(class, Ash.Error.Query.NotFound) -> GRPC.Status.not_found()
        is_struct(class, Ash.Error.Invalid) and has_not_found?.(class.errors) -> GRPC.Status.not_found()
        is_struct(class, Ash.Error.Invalid) -> GRPC.Status.invalid_argument()
        is_struct(class, Ash.Error.Forbidden) -> GRPC.Status.permission_denied()
        true -> GRPC.Status.internal()
      end

    %GRPC.RPCError{status: status, message: Exception.message(class)}
  rescue
    _ -> %GRPC.RPCError{status: GRPC.Status.internal(), message: inspect(error)}
  end
end
