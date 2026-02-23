# frozen_string_literal: true

require_relative "execution_modules/elasticsearch_execution"

module Noiseless
  module Adapters
    class Elasticsearch < Adapter
      include ExecutionModules::ElasticsearchExecution

      def initialize(hosts: [], **connection_params)
        # Ensure we always have at least one host
        hosts_array = Array(hosts)
        default_port = ENV["ELASTICSEARCH_PORT"] || 9200
        @hosts = hosts_array.empty? ? ["http://localhost:#{default_port}"] : hosts_array
        @connection_params = connection_params

        # Initialize HTTP clients for each host
        @clients = {}
        @hosts.each do |host|
          endpoint = Async::HTTP::Endpoint.parse(host)
          @clients[host] = Async::HTTP::Client.new(endpoint)
        end

        super(hosts: @hosts, **connection_params)
      end

      # Cluster health API - needed for Rails healthcheck
      def cluster
        @cluster ||= ClusterAPI.new(self)
      end

      # Indices API - needed for index management operations
      def indices
        @indices ||= IndicesAPI.new(self)
      end

      class ClusterAPI
        def initialize(adapter)
          @adapter = adapter
        end

        def health(**)
          Sync do
            @adapter.send(:execute_cluster_health, **)
          end
        end
      end

      class IndicesAPI
        def initialize(adapter)
          @adapter = adapter
        end

        def get(index:)
          @adapter.execute_index_exists?(index) ? { index => {} } : raise("Index not found")
        end

        def stats(index:)
          # Return basic stats structure
          { "indices" => { index => {} } }
        end

        def refresh(index:)
          # Refresh the index to make documents immediately searchable
          @adapter.send(:execute_refresh_index, index)
        end
      end
    end
  end
end
