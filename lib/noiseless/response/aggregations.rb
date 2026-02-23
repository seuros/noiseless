# frozen_string_literal: true

module Noiseless
  module Response
    class Aggregations
      include Enumerable

      def initialize(aggs_hash)
        @aggs_hash = aggs_hash || {}
      end

      def [](key)
        @aggs_hash[key.to_s]
      end

      delegate :keys, to: :@aggs_hash

      def each(&)
        return enum_for(__method__) unless block_given?

        @aggs_hash.each(&)
      end

      delegate :empty?, to: :@aggs_hash

      delegate :size, to: :@aggs_hash

      def to_h
        @aggs_hash
      end

      # Handle method conflicts with Enumerable methods
      def method_missing(method_name, *args, &)
        if @aggs_hash.key?(method_name.to_s)
          @aggs_hash[method_name.to_s]
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @aggs_hash.key?(method_name.to_s) || super
      end
    end
  end
end
