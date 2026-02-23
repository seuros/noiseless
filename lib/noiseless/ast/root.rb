# frozen_string_literal: true

module Noiseless
  module AST
    class Root < Node
      attr_reader :indexes, :bool, :sort, :paginate, :vector, :collapse, :search_after,
                  :aggregations, :hybrid, :pipeline, :image_query, :conversation, :joins,
                  :remove_duplicates, :facet_sample_slope, :pinned_hits

      def initialize(indexes:, bool:, sort:, paginate:, vector: nil, collapse: nil, search_after: nil,
                     aggregations: [], hybrid: nil, pipeline: nil, image_query: nil, conversation: nil, joins: [],
                     remove_duplicates: nil, facet_sample_slope: nil, pinned_hits: nil)
        super()
        @indexes      = Array(indexes)
        @bool         = bool
        @sort         = sort
        @paginate     = paginate
        @vector       = vector
        @collapse     = collapse
        @search_after = search_after
        @aggregations = aggregations
        @hybrid       = hybrid
        @pipeline     = pipeline
        @image_query  = image_query
        @conversation = conversation
        @joins        = joins
        @remove_duplicates = remove_duplicates
        @facet_sample_slope = facet_sample_slope
        @pinned_hits = pinned_hits
      end

      def vector_search?
        !@vector.nil?
      end

      def hybrid_search?
        !@hybrid.nil?
      end

      def has_pipeline?
        !@pipeline.nil?
      end

      def collapsed?
        !@collapse.nil?
      end

      def cursor_pagination?
        !@search_after.nil?
      end

      def aggregated?
        @aggregations.any?
      end

      def image_search?
        !@image_query.nil?
      end

      def conversational?
        !@conversation.nil?
      end

      def has_joins?
        @joins.any?
      end
    end
  end
end
