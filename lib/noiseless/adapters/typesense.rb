# frozen_string_literal: true


module Noiseless
  module Adapters
    class Typesense < Adapter
      include ExecutionModules::TypesenseExecution

      ClusterAPI = Adapters::ClusterAPI

      # Cluster health API - needed for Rails healthcheck
      def cluster
        @cluster ||= ClusterAPI.new(self)
      end

      # Indices API - needed for index management operations
      def indices
        @indices ||= IndicesAPI.new(self)
      end

      class IndicesAPI < Adapters::IndicesAPI
        def refresh(index: nil)
          # Typesense doesn't require explicit refresh - documents are immediately available
          { "_shards" => { "total" => 1, "successful" => 1, "failed" => 0 } }
        end
      end

      private

      def default_port
        ENV["TYPESENSE_PORT"] || 8108
      end
    end
  end
end
