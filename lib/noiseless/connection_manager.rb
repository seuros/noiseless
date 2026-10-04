# frozen_string_literal: true

module Noiseless
  class ConnectionManager
    def initialize
      @clients = {}
      @configs = {}
    end

    # Register a named client statically from YAML (boot-time only).
    # request_timeout: :default uses the adapter default, nil disables the deadline.
    # Any other keys (e.g. api_key) are passed to the adapter unchanged.
    def register(name, adapter:, hosts:, timeout: nil, request_timeout: :default, **options)
      @configs[name.to_sym] = { adapter: adapter, hosts: hosts, timeout: timeout, request_timeout: request_timeout,
                                options: options }
    end

    # Retrieve a client; defaults to :primary
    def client(name = :primary)
      name = name.to_sym

      # Lazy-load the adapter only when actually used
      @clients[name] ||= begin
        config = @configs.fetch(name) { raise "Unknown connection: #{name}" }
        params = { **config[:options], hosts: config[:hosts] }
        params[:timeout] = config[:timeout] unless config[:timeout].nil?
        params[:request_timeout] = config[:request_timeout] unless config[:request_timeout] == :default
        Adapters.lookup(config[:adapter], **params)
      end
    end
  end
end
