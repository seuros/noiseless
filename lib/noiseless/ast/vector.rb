# frozen_string_literal: true

module Noiseless
  module AST
    # Vector search node for semantic/embedding-based search
    # Used with pgvector in PostgreSQL or knn in OpenSearch
    class Vector < Node
      attr_reader :field, :embedding, :k, :distance_metric

      # @param field [Symbol, String] The embedding column/field
      # @param embedding [Array<Float>] The query embedding vector
      # @param k [Integer] Number of nearest neighbors (default: 10)
      # @param distance_metric [Symbol] :cosine, :l2, or :inner_product (default: :cosine)
      def initialize(field, embedding, k: 10, distance_metric: :cosine)
        super()
        @field = field
        @embedding = embedding
        @k = k
        @distance_metric = distance_metric
      end

      def dimension
        @embedding&.size || 0
      end
    end
  end
end
