# AshGrpc

A gRPC extension for the [Ash Framework](https://ash-hq.org). Maps Ash resource actions to gRPC methods, generates `.proto` definitions and protobuf message modules, and wires a generic dispatcher to a `GRPC.Server` — all from a declarative DSL.

```
Ash.Resource + grpc do ... end
        │
        ▼ (compile-time)
  Proto message modules    gRPC service module
  (Request/Response)       (GRPC.Server.Service)
        │                         │
        └──────────┬──────────────┘
                   ▼
           AshGrpc.Server   ← dispatches to Ash actions
```

## Features

- Declarative `grpc do` DSL on any Ash resource
- Auto-generates protobuf message modules from resource attributes and actions
- Supports unary, server-streaming, and client-streaming RPC patterns
- Built-in interceptors: authentication, OpenTelemetry trace propagation, context injection
- Proto introspection via `AshGrpc.Resource.Info`

## Getting Started

### Requirements

- Elixir ~> 1.16
- Ash ~> 3.0
- A running gRPC-compatible client or `grpcurl` for testing

### Install

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:ash_grpc, "~> 0.1"},
    {:ash, "~> 3.0"},
    {:grpc, "~> 0.9"},
    {:protobuf, "~> 0.13"},
    {:jason, "~> 1.4"},
    # Optional: OpenTelemetry trace propagation
    {:opentelemetry_api, "~> 1.3", optional: true}
  ]
end
```

Then run:

```bash
mix deps.get
```

### Define a resource

Add the `AshGrpc.Resource` extension and a `grpc` block to any Ash resource:

```elixir
defmodule MyApp.Inventory.Unit do
  use Ash.Resource,
    domain: MyApp.Inventory,
    extensions: [AshGrpc.Resource]

  grpc do
    service_name "myapp.inventory.UnitService"
    package "myapp.inventory"

    method :get_unit,     action: :read,    get?: true
    method :list_units,   action: :read,    server_stream: true
    method :create_unit,  action: :create
    method :update_unit,  action: :update
    method :destroy_unit, action: :destroy
  end

  attributes do
    uuid_primary_key :id
    attribute :name,     :string, allow_nil?: false
    attribute :sku,      :string, allow_nil?: false
    attribute :quantity, :integer, default: 0
    attribute :active,   :boolean, default: true
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end
end
```

### Start the gRPC server

```elixir
defmodule MyApp.GrpcEndpoint do
  use GRPC.Endpoint

  intercept AshGrpc.Interceptors.Auth
  intercept AshGrpc.Interceptors.Telemetry  # optional
  run AshGrpc.Server, services: [MyApp.Inventory.Unit]
end
```

Add to your supervision tree:

```elixir
{GRPC.Server.Supervisor, endpoint: MyApp.GrpcEndpoint, port: 50051}
```

### Try it

Run the bundled demo server to see a working example without any setup:

```bash
elixir demo_server.exs
```

Or explore interactively:

```bash
livebook server ash_grpc_demo.livemd
```

## Project structure

```
lib/ash_grpc/
├── codec.ex              # Protobuf ↔ Ash struct conversion
├── interceptors/         # Auth, telemetry, context interceptors
├── proto/                # Proto generation from Ash resource DSL
├── resource/             # grpc DSL entities, verifiers, transformers
└── server/               # GRPC.Server dispatcher

demo_server.exs           # Standalone runnable example
ash_grpc_demo.livemd      # Interactive Livebook walkthrough
```

## License

MIT
