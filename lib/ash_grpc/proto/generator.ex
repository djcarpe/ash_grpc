defmodule AshGrpc.Proto.Generator do
  @moduledoc """
  Generates a proto3 `.proto` definition string from a resource's `grpc` DSL.

  For each method it emits a request message (derived from the action's
  accepted arguments + identifying fields) and a response message (derived
  from the resource's public attributes, or `method.fields` if restricted),
  plus a service block with one `rpc` per method.
  """

  alias AshGrpc.Resource.Info
  alias AshGrpc.Proto.TypeMapping

  @doc "Generate the full .proto source for a resource."
  def generate(resource) do
    package = Info.package!(resource)
    service_name = Info.service_name!(resource) |> last_segment()
    methods = Info.methods(resource)

    {messages, imports} = build_messages(resource, methods)

    [
      ~s(syntax = "proto3";\n),
      "package #{package};\n",
      render_imports(imports),
      "\n",
      render_service(service_name, methods),
      "\n",
      messages
    ]
    |> IO.iodata_to_binary()
  end

  defp render_imports([]), do: ""

  defp render_imports(imports) do
    imports
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map_join("", &"import \"#{&1}\";\n")
  end

  defp render_service(name, methods) do
    rpcs =
      Enum.map_join(methods, "", fn m ->
        req = msg_name(m, :request)
        resp = msg_name(m, :response)
        req_decl = if m.client_stream, do: "stream #{req}", else: req
        resp_decl = if m.server_stream, do: "stream #{resp}", else: resp
        doc = if m.description, do: "  // #{m.description}\n", else: ""
        "#{doc}  rpc #{m.rpc_name}(#{req_decl}) returns (#{resp_decl});\n"
      end)

    "service #{name} {\n#{rpcs}}\n"
  end

  defp build_messages(resource, methods) do
    {blocks, imports} =
      Enum.reduce(methods, {[], []}, fn method, {blocks, imports} ->
        action = Ash.Resource.Info.action(resource, method.action)
        {req_block, req_imports} = request_message(resource, method, action)
        {resp_block, resp_imports} = response_message(resource, method)
        {[blocks, req_block, resp_block], imports ++ req_imports ++ resp_imports}
      end)

    {IO.iodata_to_binary(blocks), imports}
  end

  # Request: identity fields (for get/update/destroy) + accepted action inputs.
  defp request_message(resource, method, action) do
    fields =
      identity_fields(resource, method, action) ++ action_input_fields(resource, action)

    fields = Enum.uniq_by(fields, fn {name, _, _} -> name end)
    render_message(msg_name(method, :request), fields)
  end

  # Response: resource public attributes (optionally restricted by :fields).
  defp response_message(resource, method) do
    attrs =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> maybe_restrict(method.fields)

    fields = Enum.map(attrs, &attr_field/1)

    case method do
      %{server_stream: true} -> render_message(msg_name(method, :response), fields)
      %{get?: true} -> render_message(msg_name(method, :response), fields)
      _ ->
        # non-streaming list reads wrap repeated records
        if list_response?(method) do
          inner_name = msg_name(method, :response) <> "Record"
          {inner_block, imports} = render_message(inner_name, fields)
          wrapper = "message #{msg_name(method, :response)} {\n  repeated #{inner_name} records = 1;\n}\n\n"
          {inner_block <> wrapper, imports}
        else
          render_message(msg_name(method, :response), fields)
        end
    end
  end

  defp list_response?(%{action: _} = method), do: not method.get? and not method.server_stream

  defp identity_fields(resource, %{get?: true}, %{type: :read}) do
    pkey = Ash.Resource.Info.primary_key(resource)
    Enum.map(pkey, fn name ->
      attr = Ash.Resource.Info.attribute(resource, name)
      attr_field(attr)
    end)
  end

  defp identity_fields(resource, _method, %{type: type}) when type in [:update, :destroy] do
    pkey = Ash.Resource.Info.primary_key(resource)
    Enum.map(pkey, fn name ->
      attr = Ash.Resource.Info.attribute(resource, name)
      attr_field(attr)
    end)
  end

  defp identity_fields(_resource, _method, _action), do: []

  defp action_input_fields(resource, action) do
    accepted =
      case action do
        %{type: :read} -> []
        %{accept: accept} -> accept || []
        _ -> []
      end

    attr_fields =
      Enum.map(accepted, fn name ->
        attr = Ash.Resource.Info.attribute(resource, name)
        if attr, do: attr_field(attr)
      end)
      |> Enum.reject(&is_nil/1)

    arg_fields =
      action
      |> Map.get(:arguments, [])
      |> Enum.filter(& &1.public?)
      |> Enum.map(&arg_field/1)

    attr_fields ++ arg_fields
  end

  defp maybe_restrict(attrs, nil), do: attrs

  defp maybe_restrict(attrs, fields) do
    Enum.filter(attrs, &(&1.name in fields))
  end

  defp attr_field(attr) do
    {type, repeated?} = TypeMapping.proto_type(attr)
    {to_string(attr.name), type, repeated?}
  end

  defp arg_field(arg) do
    {type, repeated?} = TypeMapping.proto_type(%{type: arg.type, constraints: arg.constraints})
    {to_string(arg.name), type, repeated?}
  end

  defp render_message(name, fields) do
    {lines, imports, _n} =
      Enum.reduce(fields, {[], [], 1}, fn {fname, ftype, repeated?}, {acc, imps, n} ->
        prefix = if repeated?, do: "repeated ", else: ""
        line = "  #{prefix}#{ftype} #{fname} = #{n};\n"
        imp = TypeMapping.well_known_import(ftype)
        {[acc, line], if(imp, do: [imp | imps], else: imps), n + 1}
      end)

    block = "message #{name} {\n#{IO.iodata_to_binary(lines)}}\n\n"
    {block, imports}
  end

  defp msg_name(method, :request), do: short(method.request)
  defp msg_name(method, :response), do: short(method.response)

  defp short(module) do
    module |> Module.split() |> List.last()
  end

  defp last_segment(name), do: name |> String.split(".") |> List.last()
end
