# frozen_string_literal: true

require "active_support"
require "active_support/core_ext"
require "active_support/notifications"
require "zeitwerk"
require "yaml"
require "erb"
require "json"
require "singleton"
require "async"
require "async/http/endpoint"
require "async/http/client"
require "async/pool"

module Noiseless
  class Error < StandardError; end

  class Configuration
    attr_accessor :connections_config, :default_connection, :default_adapter, :config_path

    def initialize
      @connections_config = {}
      @default_connection = :primary
      @default_adapter = :opensearch
      @config_path = -> { Rails.root.join("config/noiseless.yml") }
    end
  end

  def self.config
    @config ||= Configuration.new
  end

  def self.reset_config!
    @config = Configuration.new
  end

  def self.load_configuration!
    path = config.config_path.respond_to?(:call) ? config.config_path.call : config.config_path
    return unless File.exist?(path)

    # Use Rails config_for if available and using standard config path, otherwise use ActiveSupport's YAML with ERB
    standard_path = Rails.root.join("config/noiseless.yml")
    if Rails.application && path.to_s == standard_path.to_s
      # config_for already returns environment-specific config with ERB processed
      env_config = Rails.application.config_for(:noiseless)
    else
      # Use YAML.safe_load for custom config files, with ERB processing
      file_content = File.read(path)
      processed_content = ERB.new(file_content).result
      raw = YAML.safe_load(processed_content, aliases: true)
      env_config = raw[Rails.env.to_s] || {}
    end

    config.default_connection = env_config["default"].to_sym if env_config && env_config["default"]
    config.connections_config = ((env_config && env_config["connections"]) || {}).transform_keys(&:to_sym)
                                                                                 .transform_values { |v| v.transform_keys(&:to_sym) }

    # Register all connections statically from YAML - no runtime registration
    config.connections_config.each do |name, params|
      adapter_name = params[:adapter]
      hosts = params[:hosts] || []
      connections.register(name, adapter: adapter_name, hosts: hosts)
    end
  end

  def self.configure
    yield(config) if block_given?
  end

  # Global connection manager instance
  def self.connections
    @connections ||= ConnectionManager.new
  end

  # Setup Zeitwerk autoloader
  loader = Zeitwerk::Loader.for_gem
  loader.inflector.inflect("ast" => "AST", "dsl" => "DSL", "open_search" => "OpenSearch")
  loader.ignore("#{__dir__}/application_search.rb")
  loader.ignore("#{__dir__}/noiseless/test_helper.rb")
  loader.ignore("#{__dir__}/noiseless/test_case.rb")
  loader.setup
  loader.eager_load if Rails.env.test?

  # Manually require response classes since they're in a subdirectory
  require_relative "noiseless/response"
  require_relative "noiseless/response_factory"

  # Global registry instance
  def self.registry
    ModelRegistry.instance
  end

  # Convenience methods
  def self.register_model(model_class, **options)
    registry.register(model_class, options)
  end

  def self.all_models
    registry.all_models
  end

  def self.searchable_models
    registry.searchable_models
  end

  def self.multi_search(models: nil, indexes: nil, connection: nil, &block)
    search_instance = MultiSearch.new(
      models: models,
      indexes: indexes,
      connection: connection
    )

    if block
      search_instance.search(&block)
    else
      search_instance
    end
  end
end

# Load Railtie
require "noiseless/railtie"

# Test helpers must be manually required in test_helper.rb
# This prevents VCR LoadError in production environments
