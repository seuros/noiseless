# frozen_string_literal: true

module Noiseless
  module Response
    class Suggestions
      include Enumerable

      def initialize(suggestions_hash)
        @suggestions_hash = suggestions_hash || {}
      end

      def [](key)
        @suggestions_hash[key.to_s]
      end

      delegate :keys, to: :@suggestions_hash

      def each(&)
        return enum_for(__method__) unless block_given?

        @suggestions_hash.each(&)
      end

      delegate :empty?, to: :@suggestions_hash

      delegate :size, to: :@suggestions_hash

      def to_h
        @suggestions_hash
      end

      def terms
        @terms ||= extract_terms
      end

      private

      def extract_terms
        terms = []
        @suggestions_hash.each_value do |suggestion|
          next unless suggestion.is_a?(Array)

          suggestion.each do |item|
            next unless item.is_a?(Hash) && item["options"]

            item["options"].each do |option|
              terms << option["text"] if option["text"]
            end
          end
        end
        terms.uniq
      end
    end
  end
end
