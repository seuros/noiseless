# frozen_string_literal: true

module Noiseless
  class ConnectionManager
    def initialize
      @clients = {}
      @configs = {}
    end

    # Register a named client statically from YAML (boot-time only)
    def register(name, adapter:, hosts:)
      @configs[name.to_sym] = { adapter: adapter, hosts: hosts }
    end

    # Retrieve a client; defaults to :primary
    def client(name = :primary)
      name = name.to_sym

      # Lazy-load the adapter only when actually used
      @clients[name] ||= begin
        config = @configs.fetch(name) { raise "Unknown connection: #{name}" }
        Adapters.lookup(config[:adapter], hosts: config[:hosts])
      end
    end
  end
end
