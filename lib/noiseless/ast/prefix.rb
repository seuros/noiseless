# frozen_string_literal: true

module Noiseless
  module AST
    class Prefix < Node
      attr_reader :field, :value

      def initialize(field, value)
        super()
        @field = field
        @value = value
      end
    end
  end
end
