defmodule AshGrpc.Resource do
  @moduledoc """
  An Ash resource extension that maps Ash actions onto gRPC methods,
  generates `.proto` definitions and protobuf message modules from the
  resource, and wires a generic dispatcher to a `GRPC.Server`.

  ## Example

      defmodule MyApp.Units.Unit do
        use Ash.Resource,
          domain: MyApp.Units,
          extensions: [AshGrpc.Resource]

        grpc do
          service_name "myapp.units.UnitService"
          package "myapp.units"

          method :get_unit, action: :read, get?: true
          method :list_units, action: :read, server_stream: true
          method :create_unit, action: :create
          method :update_unit, action: :update
          method :destroy_unit, action: :destroy
        end

        # ...attributes, actions
      end
  """

  @method %Spark.Dsl.Entity{
    name: :method,
    target: AshGrpc.Resource.Method,
    args: [:name],
    describe: "Map an Ash action to a gRPC method.",
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The unique name of the method within this service."
      ],
      action: [
        type: :atom,
        required: true,
        doc: "The Ash action this RPC invokes."
      ],
      rpc_name: [
        type: :string,
        doc: "The wire name of the RPC. Defaults to the PascalCase of `:name`."
      ],
      request: [
        type: :atom,
        doc: "Override the generated request message module."
      ],
      response: [
        type: :atom,
        doc: "Override the generated response message module."
      ],
      server_stream: [
        type: :boolean,
        default: false,
        doc: "Stream the response (server-streaming RPC). Valid for read actions."
      ],
      client_stream: [
        type: :boolean,
        default: false,
        doc: "Stream the request (client-streaming RPC)."
      ],
      get?: [
        type: :boolean,
        default: false,
        doc: "For read actions: return a single record rather than a list."
      ],
      load: [
        type: {:list, :any},
        default: [],
        doc: "Relationships/calculations to load on the result."
      ],
      fields: [
        type: {:list, :atom},
        doc: "Restrict the generated message fields to this subset of public attributes."
      ],
      description: [
        type: :string,
        doc: "Doc comment emitted into the generated .proto."
      ]
    ]
  }

  @grpc %Spark.Dsl.Section{
    name: :grpc,
    describe: "Configure the gRPC service generated for this resource.",
    schema: [
      service_name: [
        type: :string,
        required: true,
        doc: "Fully-qualified proto service name, e.g. \"myapp.units.UnitService\"."
      ],
      package: [
        type: :string,
        doc: "Proto package. Defaults to the service_name minus its last segment."
      ],
      service: [
        type: :atom,
        doc: "Override the generated `GRPC.Service` module name."
      ],
      message_namespace: [
        type: :atom,
        doc: "Module namespace under which generated message modules are placed. " <>
               "Defaults to the resource module."
      ]
    ],
    entities: [@method]
  }

  use Spark.Dsl.Extension,
    sections: [@grpc],
    transformers: [
      AshGrpc.Resource.Transformers.SetMethodDefaults,
      AshGrpc.Resource.Transformers.SetMessageModules
    ],
    verifiers: [
      AshGrpc.Resource.Verifiers.VerifyActions,
      AshGrpc.Resource.Verifiers.VerifyStreaming
    ]
end
