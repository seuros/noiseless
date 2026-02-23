# frozen_string_literal: true

module Noiseless
  module AST
    class Collapse < Node
      attr_reader :field, :inner_hits, :max_concurrent_group_searches

      def initialize(field, inner_hits: nil, max_concurrent_group_searches: nil)
        super()
        @field = field.to_s
        @inner_hits = inner_hits
        @max_concurrent_group_searches = max_concurrent_group_searches
      end
    end
  end
end
