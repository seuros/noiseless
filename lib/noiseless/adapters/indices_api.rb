# frozen_string_literal: true

module Noiseless
  module Adapters
    # Indices API - needed for index management operations
    class IndicesAPI
      def initialize(adapter)
        @adapter = adapter
      end

      def get(index:)
        raise Noiseless::Error, "Index not found: #{index}" unless @adapter.index_exists?(index).wait

        { index => {} }
      end

      def stats(index:)
        # Return basic stats structure
        { "indices" => { index => {} } }
      end

      def refresh(index:)
        # Refresh the index to make documents immediately searchable
        @adapter.refresh_index(index).wait
      end
    end
  end
end
