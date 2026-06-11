# frozen_string_literal: true

module Noiseless
  module Adapters
    # Cluster health API - needed for Rails healthcheck
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
  end
end
