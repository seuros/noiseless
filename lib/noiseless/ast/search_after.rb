# frozen_string_literal: true

module Noiseless
  module AST
    class SearchAfter < Node
      attr_reader :values

      def initialize(values)
        super()
        @values = Array(values)
      end
    end
  end
end
