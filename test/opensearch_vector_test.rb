# frozen_string_literal: true

require "test_helper"

class OpenSearchVectorTest < ActiveSupport::TestCase
  INDEX = "noiseless_os_vectors"

  class Doc < Noiseless::Model
    def self.name = "OpenSearchVectorTest::Doc"

    search_index INDEX
    connection :opensearch
    mapping do
      properties do
        title :text
        status :keyword
        embedding :knn_vector, dimension: 3, space_type: "cosinesimil"
      end
    end
  end

  teardown { Sync { client.delete_index(INDEX).wait } }

  test "base64 vectors import, pre-filtered knn and rrf hybrid" do
    result = Noiseless::BulkImporter.new(Doc).import([{ id: 1, title: "ruby search", status: "live", embedding: [1, 0, 0] },
                                                      { id: 2, title: "go async", status: "draft", embedding: [0, 1, 0] }],
                                                     force: true)
    assert_equal 0, result[:errors]

    knn = Noiseless::QueryBuilder.new(Doc).vector(:embedding, [0.1, 0.9, 0], k: 2).filter(:status, "live")
    assert_equal ["1"], search_ids(knn)

    hybrid = Noiseless::QueryBuilder.new(Doc).hybrid("ruby", [0, 1, 0], field: :embedding, fields: [:title])
    assert_equal %w[1 2], search_ids(hybrid)
  end

  test "pipelines, workload groups and rules round-trip" do
    client.pipelines.create("noiseless_rrf", phase_results_processors: [{ "score-ranker-processor": { combination: { technique: "rrf" } } }])
    assert client.pipelines.exists?("noiseless_rrf")
    client.pipelines.delete("noiseless_rrf")
    assert_not client.pipelines.exists?("noiseless_rrf")

    name = "noiseless_#{SecureRandom.hex(4)}"
    group = client.workload_groups.create(name, resource_limits: { memory: 0.05 })
    rule = client.rules.create(:workload_group, description: "logs", value: group["_id"], index_pattern: ["logs-*"])
    client.rules.update(:workload_group, rule["id"], description: "all logs")

    assert_equal "all logs", client.rules.get(:workload_group, rule["id"])["description"]
    assert client.rules.exists?(:workload_group, rule["id"])
    assert client.rules.delete(:workload_group, rule["id"])["acknowledged"]
  ensure
    if group
      20.times do
        break client.workload_groups.delete(name)
      rescue Noiseless::RequestError
        sleep 0.25
      end
    end
  end

  private

  def client = Noiseless.connections.client(:opensearch)

  def search_ids(builder)
    Sync { client.search(builder.to_ast, response_type: :results).wait }.hits.map { it["_id"] }
  end
end
