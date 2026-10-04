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
end
