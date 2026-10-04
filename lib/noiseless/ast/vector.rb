# frozen_string_literal: true

module Noiseless
  module AST
    # Vector search node for semantic/embedding-based search
    # Used with pgvector in PostgreSQL or knn in OpenSearch
    class Vector < Node
      DISTANCE_METRICS = %i[cosine l2 euclidean inner_product].freeze

      attr_reader :field, :embedding, :k, :distance_metric

      # Embeddings are rendered into SQL literals and engine query strings, so
      # anything that is not a finite number is rejected rather than escaped.
      def self.coerce_embedding(embedding)
        values = Array(embedding).map do |value|
          number = Float(value)
          raise ArgumentError, "embedding contains a non-finite value: #{value.inspect}" unless number.finite?

          number
        end
        raise ArgumentError, "embedding must not be empty" if values.empty?

        values
      rescue TypeError => e
        raise ArgumentError, "embedding must contain only numbers (#{e.message})"
      end

      # @param field [Symbol, String] The embedding column/field
      # @param embedding [Array<Float>] The query embedding vector
      # @param k [Integer] Number of nearest neighbors (default: 10)
      # @param distance_metric [Symbol] :cosine, :l2, :euclidean or :inner_product (default: :cosine)
      def initialize(field, embedding, k: 10, distance_metric: :cosine)
        super()
        @field = field
        @embedding = embedding.nil? ? nil : self.class.coerce_embedding(embedding)
        @k = Integer(k)
        @distance_metric = distance_metric.to_sym
        return if DISTANCE_METRICS.include?(@distance_metric)

        raise ArgumentError, "distance_metric must be one of #{DISTANCE_METRICS.join(', ')}, got #{distance_metric.inspect}"
      end

      def dimension
        @embedding&.size || 0
      end
    end
  end
end
