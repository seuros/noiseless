# frozen_string_literal: true

module Noiseless
  module AST
    class Sort < Node
      attr_reader :field, :direction

      def initialize(field, direction)
        super()
        @field = field
        @direction = direction
      end
    end
  end
end
