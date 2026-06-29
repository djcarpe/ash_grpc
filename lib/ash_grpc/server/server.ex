defmodule AshGrpc.Server do
  @moduledoc """
  Generates a `GRPC.Server` implementation for a resource.

  Usage:

      defmodule MyApp.Grpc.UnitServer do
        use AshGrpc.Server,
          resource: MyApp.Units.Unit,
          service: MyApp.Units.UnitService.Service
      end

  This defines one function per method (named after the snake_cased rpc name,
  which is what `protobuf`'s `GRPC.Service` generates as the callback name),
  each delegating to `AshGrpc.Server.Dispatcher`.
  """

  defmacro __using__(opts) do
    resource = Macro.expand(Keyword.fetch!(opts, :resource), __CALLER__)
    service = Keyword.fetch!(opts, :service)

    methods = AshGrpc.Resource.Info.methods(resource)

    callbacks =
      for method <- methods do
        fun_name = callback_name(method.rpc_name)

        if method.server_stream do
          quote do
            def unquote(fun_name)(request, stream) do
              case AshGrpc.Server.Dispatcher.dispatch(
                     unquote(resource),
                     unquote(method.name),
                     request,
                     stream
                   ) do
                {:ok, _stream} -> :ok
                {:error, %GRPC.RPCError{} = err} -> raise err
              end
            end
          end
        else
          quote do
            def unquote(fun_name)(request, stream) do
              case AshGrpc.Server.Dispatcher.dispatch(
                     unquote(resource),
                     unquote(method.name),
                     request,
                     stream
                   ) do
                {:ok, reply} -> reply
                {:error, %GRPC.RPCError{} = err} -> raise err
              end
            end
          end
        end
      end

    quote do
      use GRPC.Server, service: unquote(service)

      @ash_grpc_resource unquote(resource)
      def __ash_grpc_resource__, do: @ash_grpc_resource

      unquote(callbacks)
    end
  end

  @doc "Snake-case callback name matching protobuf-elixir's generated server stub."
  def callback_name(rpc_name) do
    rpc_name
    |> Macro.underscore()
    |> String.to_atom()
  end
end
