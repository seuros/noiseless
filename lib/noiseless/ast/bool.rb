# frozen_string_literal: true

module Noiseless
  module AST
    class Bool < Node
      attr_reader :must, :filter, :should

      def initialize(must: [], filter: [], should: [])
        super()
        @must = must
        @filter = filter
        @should = should
      end
    end
  end
end
