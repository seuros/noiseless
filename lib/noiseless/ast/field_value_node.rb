# frozen_string_literal: true

module Noiseless
  module AST
    # Base for leaf nodes that pair a single field with a value.
    class FieldValueNode < Node
      attr_reader :field, :value

      def initialize(field, value)
        super()
        @field = field
        @value = value
      end
    end
  end
end
