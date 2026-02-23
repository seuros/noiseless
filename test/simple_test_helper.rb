# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"
require "noiseless"

# Service hosts from environment (for CI) or localhost (for local dev)
ES_HOST = ENV.fetch("ELASTICSEARCH_HOST", "localhost")
ES_PORT = ENV.fetch("ELASTICSEARCH_PORT", "9200")
OS_HOST = ENV.fetch("OPENSEARCH_HOST", "localhost")
OS_PORT = ENV.fetch("OPENSEARCH_PORT", "9201")
TS_HOST = ENV.fetch("TYPESENSE_HOST", "localhost")
TS_PORT = ENV.fetch("TYPESENSE_PORT", "8108")

# Configure Noiseless for tests
Noiseless.configure do |config|
  config.connections_config = {
    primary: {
      adapter: :elasticsearch,
      hosts: ["http://#{ES_HOST}:#{ES_PORT}"]
    },
    opensearch: {
      adapter: :open_search,
      hosts: ["http://#{OS_HOST}:#{OS_PORT}"]
    },
    typesense: {
      adapter: :typesense,
      hosts: ["http://#{TS_HOST}:#{TS_PORT}"]
    }
  }
end

# Register connections
Noiseless.connections.register(:primary, adapter: :elasticsearch, hosts: ["http://#{ES_HOST}:#{ES_PORT}"])
Noiseless.connections.register(:opensearch, adapter: :open_search, hosts: ["http://#{OS_HOST}:#{OS_PORT}"])
Noiseless.connections.register(:typesense, adapter: :typesense, hosts: ["http://#{TS_HOST}:#{TS_PORT}"])
