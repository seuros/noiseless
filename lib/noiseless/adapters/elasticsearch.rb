# frozen_string_literal: true


module Noiseless
  module Adapters
    class Elasticsearch < Adapter
      include ExecutionModules::ElasticsearchExecution

      ClusterAPI = Adapters::ClusterAPI
      IndicesAPI = Adapters::IndicesAPI

      # Cluster health API - needed for Rails healthcheck
      def cluster
        @cluster ||= ClusterAPI.new(self)
      end

      # Indices API - needed for index management operations
      def indices
        @indices ||= IndicesAPI.new(self)
      end

      private

      def default_port
        ENV["ELASTICSEARCH_PORT"] || 9200
      end
    end
  end
end
