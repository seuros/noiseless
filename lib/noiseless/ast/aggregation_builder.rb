# frozen_string_literal: true

module Noiseless
  module AST
    class AggregationBuilder
      attr_reader :aggregations

      def initialize
        @aggregations = []
      end

      def agg(name, type, field: nil, **, &)
        sub_aggs = []
        if block_given?
          sub_builder = AggregationBuilder.new
          sub_builder.instance_eval(&)
          sub_aggs = sub_builder.aggregations
        end

        aggregation = Aggregation.new(name, type, field: field, sub_aggregations: sub_aggs, **)
        @aggregations << aggregation
        aggregation
      end

      alias aggregation agg
    end
  end
end
