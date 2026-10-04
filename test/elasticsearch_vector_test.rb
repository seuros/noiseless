# frozen_string_literal: true

require "test_helper"

class ElasticsearchVectorTest < ActiveSupport::TestCase
  INDEX = "noiseless_es_vectors"

  class Doc < Noiseless::Model
    def self.name = "ElasticsearchVectorTest::Doc"

    search_index INDEX
    connection :primary
    mapping do
      properties do
        title :text
        status :keyword
        embedding :dense_vector, dims: 3, similarity: "cosine"
      end
    end
  end

  teardown { Sync { client.delete_index(INDEX).wait } }

  test "base64 vectors import, pre-filtered knn and weighted hybrid" do
    result = Noiseless::BulkImporter.new(Doc).import([{ id: 1, title: "ruby search", status: "live", embedding: [1, 0, 0] },
                                                      { id: 2, title: "go async", status: "draft", embedding: [0, 1, 0] }],
                                                     force: true)
    assert_equal 0, result[:errors]

    knn = Noiseless::QueryBuilder.new(Doc).vector(:embedding, [0.1, 0.9, 0], k: 2).filter(:status, "live")
    assert_equal ["1"], search_ids(knn)

    hybrid = Noiseless::QueryBuilder.new(Doc).hybrid("ruby", [0, 1, 0], field: :embedding, fields: [:title])
    assert_equal %w[1 2], search_ids(hybrid)
  end

  private

  def client = Noiseless.connections.client(:primary)

  def search_ids(builder)
    Sync { client.search(builder.to_ast, response_type: :results).wait }.hits.map { it["_id"] }
  end
end
