# frozen_string_literal: true

module Noiseless
  module Response
    class Empty < Base
      EMPTY_RESPONSE = {
        "hits" => { "total" => { "value" => 0 }, "hits" => [] },
        "took" => 0
      }.freeze

      def initialize(model_class = nil)
        super(EMPTY_RESPONSE, model_class)
      end

      def each
        return enum_for(__method__) unless block_given?
      end
    end
  end
end
