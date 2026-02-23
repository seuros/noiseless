# frozen_string_literal: true

module Noiseless
  module AST
    # Hybrid search node combining text and vector search
    # Supports weighted combination of BM25 text scores and kNN vector scores
    class Hybrid < Node
      attr_reader :text_query, :vector, :text_weight, :vector_weight

      # @param text_query [String] The text query for BM25 matching
      # @param vector [AST::Vector] The vector search node
      # @param text_weight [Float] Weight for text search score (0.0-1.0)
      # @param vector_weight [Float] Weight for vector search score (0.0-1.0)
      def initialize(text_query, vector, text_weight: 0.5, vector_weight: 0.5)
        super()
        @text_query = text_query
        @vector = vector
        @text_weight = text_weight
        @vector_weight = vector_weight
      end

      def balanced?
        @text_weight == @vector_weight
      end

      def text_dominant?
        @text_weight > @vector_weight
      end

      def vector_dominant?
        @vector_weight > @text_weight
      end
    end
  end
end
