# frozen_string_literal: true

module Noiseless
  # A dense vector document field. Elasticsearch and OpenSearch send it as a
  # base64 float32 string, which is far smaller and faster to ingest than a
  # JSON float array; every other encoder sees a plain array.
  Embedding = Data.define(:values) do
    def initialize(values:)
      super(values: AST::Vector.coerce_embedding(values))
    end

    def to_a = values
    def as_json(*) = values
    def to_json(*) = values.to_json(*)
  end

  class Embedding
    VECTOR_TYPES = %w[dense_vector knn_vector].freeze

    def self.vector_fields(model_class)
      return [] unless model_class.respond_to?(:mapping) && model_class.mapping

      properties = MappingDefinitionProcessor.process(model_class.mapping).dig(:mappings, :properties).to_h
      properties.filter_map { |name, config| name.to_s if VECTOR_TYPES.include?(config[:type].to_s) }
    end

    def self.wrap(document, fields)
      return document if fields.empty? || !document.respond_to?(:to_h)

      document.to_h.to_h { |key, value| [key, fields.include?(key.to_s) && value.is_a?(Array) ? new(values: value) : value] }
    end
  end
end
