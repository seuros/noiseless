# frozen_string_literal: true

module Noiseless
  module AST
    class CombinedFields < Node
      attr_reader :query, :fields, :operator, :minimum_should_match, :zero_terms_query,
                  :auto_generate_synonyms_phrase_query

      def initialize(query, fields, operator: nil, minimum_should_match: nil, zero_terms_query: nil,
                     auto_generate_synonyms_phrase_query: nil)
        super()
        @query = query
        @fields = Array(fields).map(&:to_s)
        @operator = operator
        @minimum_should_match = minimum_should_match
        @zero_terms_query = zero_terms_query
        @auto_generate_synonyms_phrase_query = auto_generate_synonyms_phrase_query
      end

      def options
        {}.tap do |opts|
          opts[:operator] = @operator if @operator
          opts[:minimum_should_match] = @minimum_should_match if @minimum_should_match
          opts[:zero_terms_query] = @zero_terms_query if @zero_terms_query
          unless @auto_generate_synonyms_phrase_query.nil?
            opts[:auto_generate_synonyms_phrase_query] =
              @auto_generate_synonyms_phrase_query
          end
        end
      end
    end
  end
end
