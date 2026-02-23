# frozen_string_literal: true

require "minitest/autorun"
require "minitest/spec"
require "active_support/all"
require_relative "../lib/noiseless"

describe Noiseless do
  before do
    # Reset configuration before each test
    Noiseless.config.connections_config = {}
    Noiseless.config.default_connection = :primary
    Noiseless.config.default_adapter = :elasticsearch
  end

  describe "Configuration" do
    it "has default configuration values" do
      _(Noiseless.config.default_connection).must_equal :primary
      _(Noiseless.config.default_adapter).must_equal :elasticsearch
      _(Noiseless.config.connections_config).must_equal({})
    end

    it "allows configuration via block" do
      Noiseless.configure do |config|
        config.default_connection = :secondary
        config.default_adapter = :opensearch
      end

      _(Noiseless.config.default_connection).must_equal :secondary
      _(Noiseless.config.default_adapter).must_equal :opensearch
    end

    it "loads configuration from YAML file" do
      # Create temporary config file
      config_content = {
        "test" => {
          "default" => "test_connection",
          "connections" => {
            "test_connection" => {
              "adapter" => "elasticsearch",
              "host" => "localhost",
              "port" => 9200
            }
          }
        }
      }

      config_path = "/tmp/test_noiseless.yml"
      File.write(config_path, config_content.to_yaml)

      # Stub Rails.env if needed
      unless defined?(Rails)
        Rails = Class.new do
          def self.env
            "test"
          end
        end
      end

      Noiseless.config.config_path = config_path
      Noiseless.load_configuration!

      _(Noiseless.config.default_connection).must_equal :test_connection
      _(Noiseless.config.connections_config[:test_connection][:adapter]).must_equal "elasticsearch"
      _(Noiseless.config.connections_config[:test_connection][:host]).must_equal "localhost"
      _(Noiseless.config.connections_config[:test_connection][:port]).must_equal 9200

      # Cleanup
      FileUtils.rm_f(config_path)
    end
  end

  describe "ConnectionManager" do
    before do
      @connection_manager = Noiseless::ConnectionManager.new
    end

    it "registers and retrieves clients" do
      # Mock adapter
      mock_adapter = Minitest::Mock.new

      Noiseless::Adapters.stub :lookup, mock_adapter do
        @connection_manager.register(:test, adapter: :elasticsearch, params: { host: "localhost" })

        client = @connection_manager.client(:test)
        _(client).must_equal mock_adapter
      end
    end

    it "raises error for unknown connection" do
      error = _ { @connection_manager.client(:unknown) }.must_raise RuntimeError
      _(error.message).must_match(/Unknown connection: unknown/)
    end
  end

  describe "AST Nodes" do
    it "creates Match nodes" do
      node = Noiseless::AST::Match.new("title", "Ruby")
      _(node.field).must_equal "title"
      _(node.value).must_equal "Ruby"
    end

    it "creates Filter nodes" do
      node = Noiseless::AST::Filter.new("status", "active")
      _(node.field).must_equal "status"
      _(node.value).must_equal "active"
    end

    it "creates Sort nodes" do
      node = Noiseless::AST::Sort.new("created_at", :desc)
      _(node.field).must_equal "created_at"
      _(node.direction).must_equal :desc
    end

    it "creates Paginate nodes" do
      node = Noiseless::AST::Paginate.new(2, 50)
      _(node.page).must_equal 2
      _(node.per_page).must_equal 50
    end

    it "creates Bool nodes" do
      must_nodes = [Noiseless::AST::Match.new("title", "Ruby")]
      filter_nodes = [Noiseless::AST::Filter.new("status", "active")]

      node = Noiseless::AST::Bool.new(must: must_nodes, filter: filter_nodes)
      _(node.must).must_equal must_nodes
      _(node.filter).must_equal filter_nodes
    end

    it "creates Root nodes" do
      bool_node = Noiseless::AST::Bool.new
      sort_nodes = [Noiseless::AST::Sort.new("created_at", :desc)]
      paginate_node = Noiseless::AST::Paginate.new(1, 20)

      node = Noiseless::AST::Root.new(
        indexes: ["posts"],
        bool: bool_node,
        sort: sort_nodes,
        paginate: paginate_node
      )

      _(node.indexes).must_equal ["posts"]
      _(node.bool).must_equal bool_node
      _(node.sort).must_equal sort_nodes
      _(node.paginate).must_equal paginate_node
    end
  end

  describe "QueryBuilder" do
    before do
      @model = Class.new(Noiseless::Model) do
        def self.name
          "TestModel"
        end
      end
    end

    it "builds AST from query methods" do
      builder = Noiseless::QueryBuilder.new(@model)
      builder.match("title", "Ruby")
             .filter("status", "published")
             .sort("created_at", :desc)
             .paginate(page: 2, per_page: 25)

      ast = builder.to_ast

      _(ast).must_be_instance_of Noiseless::AST::Root
      _(ast.indexes).must_equal ["test_models"]
      _(ast.bool.must.size).must_equal 1
      _(ast.bool.filter.size).must_equal 1
      _(ast.sort.size).must_equal 1
      _(ast.paginate.page).must_equal 2
      _(ast.paginate.per_page).must_equal 25
    end

    it "allows dynamic index specification" do
      builder = Noiseless::QueryBuilder.new(@model)
      builder.indexes(%w[custom_index another_index])

      ast = builder.to_ast
      _(ast.indexes).must_equal %w[custom_index another_index]
    end
  end

  describe "Instrumentation" do
    it "instruments events with ActiveSupport::Notifications" do
      instrumented_class = Class.new do
        include Noiseless::Instrumentation
      end

      events = []
      ActiveSupport::Notifications.subscribe("noiseless.test") do |name, _start, _finish, _id, payload|
        events << { name: name, payload: payload }
      end

      instance = instrumented_class.new
      instance.instrument(:test, { key: "value" }) do
        "test_result"
      end

      _(events.size).must_equal 1
      _(events.first[:name]).must_equal "noiseless.test"
      _(events.first[:payload]).must_equal({ key: "value" })
    end
  end

  describe "Adapters" do
    it "looks up adapters by name" do
      adapter = Noiseless::Adapters.lookup(:elasticsearch, { host: "localhost" })
      _(adapter).must_be_instance_of Noiseless::Adapters::Elasticsearch
    end

    it "raises error for unknown adapter" do
      error = _ { Noiseless::Adapters.lookup(:unknown) }.must_raise ArgumentError
      _(error.message).must_match(/Unknown adapter: unknown/)
    end
  end

  describe "Mapping" do
    it "converts document to hash" do
      doc = { title: "Test", content: "Content" }
      mapping = Noiseless::Mapping.new(doc)
      _(mapping.to_h).must_equal doc
    end

    it "deserializes hits" do
      hit = { "_source" => { "title" => "Test" } }
      result = Noiseless::Mapping.deserialize(hit)
      _(result).must_equal({ "title" => "Test" })
    end
  end
end
