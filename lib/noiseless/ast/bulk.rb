# frozen_string_literal: true

module Noiseless
  module AST
    class Bulk < Node
      attr_reader :operations

      def initialize(operations)
        super()
        @operations = operations
      end

      def ==(other)
        other.is_a?(self.class) && operations == other.operations
      end
    end
  end
end
