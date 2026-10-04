# frozen_string_literal: true

require "test_helper"

class PointInTimeTest < ActiveSupport::TestCase
  INDEX = "noiseless_pit_pages"

  test "each_page walks every hit with a point in time on Elasticsearch and OpenSearch" do
    model = Class.new(Noiseless::Model) { def self.name = "PointInTimeProbe" }

    %i[primary opensearch].each do |connection|
      client = Noiseless.connections.client(connection)
      Sync do
        client.bulk(Array.new(5) { |i| { index: { _index: INDEX, _id: i + 1, data: { n: i + 1 } } } }, refresh: true).wait
      end

      ast = Noiseless::QueryBuilder.new(model).indexes([INDEX]).sort(:n, :asc).paginate(per_page: 2).to_ast
      pages = client.each_page(ast).map { |page| page.hits.map { it["_id"] } }

      assert_equal [%w[1 2], %w[3 4], %w[5]], pages, connection.to_s
    ensure
      Sync { client.delete_index(INDEX).wait }
    end
  end
end
