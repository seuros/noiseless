# frozen_string_literal: true

module Noiseless
  class ResponseFactory
    def self.create(raw_response, model_class: nil, response_type: nil, query_hash: nil)
      # Auto-detect response type based on model class and preferences
      response_type ||= detect_response_type(model_class)

      response = case response_type
                 when :records
                   Response::Records.new(raw_response, model_class)
                 else # :results or unknown
                   Response::Results.new(raw_response, model_class)
                 end

      # Include pagination information if query hash is provided
      response.include_pagination_info(query_hash) if query_hash

      response
    end

    def self.detect_response_type(model_class)
      # If model_class responds to ActiveRecord-like methods, default to :records
      if model_class.respond_to?(:where) &&
         model_class.respond_to?(:find)
        :records
      else
        :results
      end
    end
  end
end
