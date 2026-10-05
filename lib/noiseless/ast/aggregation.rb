# frozen_string_literal: true

module Noiseless
  module AST
    class Aggregation < Node
      attr_reader :name, :type, :field, :options, :sub_aggregations

      METRIC_TYPES = %i[avg sum min max cardinality value_count stats extended_stats percentiles].freeze
      BUCKET_TYPES = %i[terms histogram date_histogram range date_range filter filters nested].freeze

      def initialize(name, type, field: nil, sub_aggregations: [], **options)
        super()
        @name = name.to_s
        @type = type.to_sym
        @field = field&.to_s
        @options = options
        @sub_aggregations = sub_aggregations
      end

      def metric?
        METRIC_TYPES.include?(@type)
      end

      def bucket?
        BUCKET_TYPES.include?(@type)
      end

      def add_sub_aggregation(aggregation)
        @sub_aggregations << aggregation
      end
    end
  end
end
