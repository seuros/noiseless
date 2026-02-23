# frozen_string_literal: true

require_relative "execution_modules/postgresql_execution"

module Noiseless
  module Adapters
    # PostgreSQL adapter for noiseless - uses pg_trgm, unaccent, and pgvector
    # Provides search capabilities using native PostgreSQL extensions as:
    # - Fallback when OpenSearch/Elasticsearch is unavailable
    # - Simple queries that don't need full search cluster overhead
    # - Semantic/vector search via pgvector
    #
    # Required extensions:
    #   CREATE EXTENSION IF NOT EXISTS pg_trgm;
    #   CREATE EXTENSION IF NOT EXISTS unaccent;
    #   CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
    #   CREATE EXTENSION IF NOT EXISTS vector;  -- for pgvector
    #
    class Postgresql < Adapter
      include ExecutionModules::PostgresqlExecution

      attr_reader :model_class_cache

      def initialize(hosts: nil, **connection_params) # rubocop:disable Lint/UnusedMethodArgument
        @connection_params = connection_params
        @model_class_cache = {}

        # Verify extensions on initialization (optional, can be disabled)
        verify_extensions! unless connection_params[:skip_extension_check]

        super(hosts: [], **connection_params)
      end

      def async_context?
        # PostgreSQL queries don't need async HTTP context
        # but we still wrap in Async for consistency with other adapters
        false
      end

      # Override AST conversion to build PostgreSQL-compatible query
      def ast_to_hash(ast_node)
        {
          bool: ast_node.bool,
          sort: ast_node.sort,
          paginate: ast_node.paginate,
          indexes: ast_node.indexes,  # maps to table/model
          vector: ast_node.vector     # for pgvector semantic search
        }
      end

      # Override search to return synchronously (no HTTP calls needed)
      def search(ast_node, model_class: nil, response_type: nil, **)
        query_hash = ast_to_hash(ast_node)

        Async do
          raw_response = instrument(:search, indexes: ast_node.indexes, query: query_hash) do
            execute_search(query_hash, model_class: model_class, **)
          end

          ResponseFactory.create(
            raw_response,
            model_class: model_class,
            response_type: response_type,
            query_hash: build_pagination_from_ast(ast_node)
          )
        end
      end

      # Register model for this adapter (caches table info)
      def register_model(model_class, index_name:)
        @model_class_cache[index_name] = model_class
      end

      # Cluster health check - always healthy for PostgreSQL
      def cluster
        @cluster ||= ClusterAPI.new(self)
      end

      # Index operations - no-op for PostgreSQL (data lives in tables)
      def indices
        @indices ||= IndicesAPI.new(self)
      end

      class ClusterAPI
        def initialize(adapter)
          @adapter = adapter
        end

        def health(**)
          # Check PostgreSQL connectivity and extensions
          {
            "cluster_name" => "postgresql",
            "status" => @adapter.extensions_available? ? "green" : "yellow",
            "number_of_nodes" => 1,
            "active_primary_shards" => 1,
            "extensions" => @adapter.available_extensions
          }
        end
      end

      class IndicesAPI
        def initialize(adapter)
          @adapter = adapter
        end

        def get(index:)
          # Return table info as index info
          { index => { "mappings" => {}, "settings" => {} } }
        end

        def stats(index:)
          { "indices" => { index => {} } }
        end

        def refresh(index:) # rubocop:disable Lint/UnusedMethodArgument
          # No-op for PostgreSQL - queries always see latest data
          { "_shards" => { "total" => 1, "successful" => 1, "failed" => 0 } }
        end
      end

      def extensions_available?
        @extensions_available ||= check_extensions
      end

      def available_extensions
        @available_extensions ||= detect_extensions
      end

      private

      def verify_extensions!
        missing = required_extensions - available_extensions
        return if missing.empty?

        Rails.logger.warn(
          "Noiseless PostgreSQL adapter: Missing extensions: #{missing.join(', ')}. " \
          "Some search features may be limited."
        )
      end

      def required_extensions
        %w[pg_trgm unaccent]
      end

      def check_extensions
        required_extensions.all? { |ext| available_extensions.include?(ext) }
      end

      def detect_extensions
        result = ActiveRecord::Base.connection.execute(<<~SQL.squish)
          SELECT extname FROM pg_extension
          WHERE extname IN ('pg_trgm', 'unaccent', 'fuzzystrmatch', 'vector', 'btree_gin', 'btree_gist')
        SQL
        result.pluck("extname")
      rescue StandardError => e
        Rails.logger.error("Failed to detect PostgreSQL extensions: #{e.message}")
        []
      end

      def build_pagination_from_ast(ast_node)
        paginate = ast_node.paginate
        return { from: 0, size: 20 } unless paginate

        {
          from: (paginate.page - 1) * paginate.per_page,
          size: paginate.per_page
        }
      end
    end
  end
end
