# frozen_string_literal: true

module Noiseless
  module Adapters
    # Indices API - needed for index management operations
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
