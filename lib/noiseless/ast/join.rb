# frozen_string_literal: true

module Noiseless
  module AST
    # Join node for cross-collection queries (Typesense feature)
    # Allows including related documents from other collections. The relation
    # comes from a reference field in the collection schema.
    class Join < Node
      attr_reader :collection, :include_fields, :strategy

      # @param collection [String, Symbol] The collection to join
      # @param include_fields [Array<String, Symbol>] Fields to include from joined collection
      # @param strategy [Symbol] Join strategy :left or :inner (default: :left)
      def initialize(collection, include_fields: [], strategy: :left)
        super()
        @collection = collection.to_s
        @include_fields = Array(include_fields).map(&:to_s)
        @strategy = strategy
      end

      def left_join?
        @strategy == :left
      end

      def inner_join?
        @strategy == :inner
      end
    end
  end
end
