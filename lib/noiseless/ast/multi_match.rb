# frozen_string_literal: true

module Noiseless
  module AST
    class MultiMatch
      attr_reader :query, :fields, :options

      def initialize(query, fields, **options)
        @query = query
        @fields = Array(fields)
        @options = options
      end

      def to_hash
        {
          multi_match: {
            query: @query,
            fields: @fields
          }.merge(@options)
        }
      end
    end
  end
end
