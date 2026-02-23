# frozen_string_literal: true

require_relative "execution_modules/opensearch_execution"

module Noiseless
  module Adapters
    class OpenSearch < Adapter
      include ExecutionModules::OpensearchExecution

      def initialize(hosts: [], **connection_params)
        # Ensure we always have at least one host
        hosts_array = Array(hosts)
        default_port = ENV["OPENSEARCH_PORT"] || 9200
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

      # OpenSearch-specific features
      def point_in_time_search(ast_node, pit_id:, **)
        query_hash = ast_to_hash(ast_node)
        Async do
          execute_point_in_time_search(query_hash, pit_id: pit_id, **)
        end
      end

      def search_template(template_id:, params: {}, **)
        Async do
          execute_search_template(template_id: template_id, params: params, **)
        end
      end

      # Cluster health API - needed for Rails healthcheck
      def cluster
        @cluster ||= ClusterAPI.new(self)
      end

      # Indices API - needed for index management operations
      def indices
        @indices ||= IndicesAPI.new(self)
      end

      # Search Pipelines API - OpenSearch 3.x feature
      def pipelines
        @pipelines ||= PipelinesAPI.new(self)
      end

      # Query Rules API - OpenSearch 3.x feature
      def rules
        @rules ||= RulesAPI.new(self)
      end

      # Raw search for CommonShare compatibility
      def search_raw(query_body, indexes: [], **)
        Async do
          execute_search(query_body, indexes: indexes, **)
        end
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

      # Search Pipelines API for OpenSearch 3.x
      # Pipelines can include request and response processors for neural search, reranking, etc.
      class PipelinesAPI
        def initialize(adapter)
          @adapter = adapter
        end

        # Create or update a search pipeline
        # @param name [String] Pipeline name
        # @param request_processors [Array<Hash>] Request phase processors
        # @param response_processors [Array<Hash>] Response phase processors
        # @param description [String, nil] Optional description
        def create(name, request_processors: [], response_processors: [], description: nil)
          Sync do
            @adapter.send(:execute_create_pipeline, name,
                          request_processors: request_processors,
                          response_processors: response_processors,
                          description: description)
          end
        end

        alias put create

        # Get a specific pipeline
        def get(name)
          Sync do
            @adapter.send(:execute_get_pipeline, name)
          end
        end

        # List all pipelines
        def list
          Sync do
            @adapter.send(:execute_list_pipelines)
          end
        end

        alias all list

        # Delete a pipeline
        def delete(name)
          Sync do
            @adapter.send(:execute_delete_pipeline, name)
          end
        end

        # Check if a pipeline exists
        def exists?(name)
          Sync do
            @adapter.send(:execute_pipeline_exists?, name)
          end
        end
      end

      # Query Rules API for OpenSearch 3.x
      # Rules allow pinning, boosting, or hiding specific results based on query patterns
      class RulesAPI
        def initialize(adapter)
          @adapter = adapter
        end

        # Create or update a rule
        # @param feature_type [String] Feature type (e.g., 'pinned_queries')
        # @param rule_id [String] Unique rule identifier
        # @param attributes [Hash] Rule matching attributes
        # @param feature_value [Hash] The feature value to apply
        def create(feature_type, rule_id, attributes:, feature_value:)
          Sync do
            @adapter.send(:execute_create_rule, feature_type, rule_id,
                          attributes: attributes,
                          feature_value: feature_value)
          end
        end

        alias put create

        # Get a specific rule
        def get(feature_type, rule_id)
          Sync do
            @adapter.send(:execute_get_rule, feature_type, rule_id)
          end
        end

        # List rules for a feature type
        def list(feature_type, search_after: nil)
          Sync do
            @adapter.send(:execute_list_rules, feature_type, search_after: search_after)
          end
        end

        alias all list

        # Delete a rule
        def delete(feature_type, rule_id)
          Sync do
            @adapter.send(:execute_delete_rule, feature_type, rule_id)
          end
        end

        # Check if a rule exists
        def exists?(feature_type, rule_id)
          Sync do
            @adapter.send(:execute_rule_exists?, feature_type, rule_id)
          end
        end
      end
    end
  end
end
