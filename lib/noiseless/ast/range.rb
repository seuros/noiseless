# frozen_string_literal: true

module Noiseless
  module AST
    class Range < Node
      attr_reader :field, :gte, :lte, :gt, :lt

      def initialize(field, gte: nil, lte: nil, gt: nil, lt: nil)
        super()
        @field = field
        @gte = gte
        @lte = lte
        @gt = gt
        @lt = lt
      end
    end
  end
end
