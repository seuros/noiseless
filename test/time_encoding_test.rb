# frozen_string_literal: true

require "test_helper"

class TimeEncodingTest < ActiveSupport::TestCase
  INDEX = "noiseless_time_encoding"

  test "times index and range-filter on Elasticsearch and Typesense" do
    model = Class.new(Noiseless::Model) { def self.name = "TimeEncodingProbe" }
    published = Time.utc(2025, 12, 11, 14, 18, 40)

    %i[primary typesense].each do |connection|
      client = Noiseless.connections.client(connection)
      Sync do
        client.create_index(INDEX, mappings: { properties: { title: { type: "text" }, published_at: { type: "date" } } }).wait
        client.bulk([{ index: { _index: INDEX, _id: 1, data: { title: "t", published_at: published } } }], refresh: true).wait
      end

      ast = Noiseless::QueryBuilder.new(model).indexes([INDEX]).range(:published_at, gte: published - 60).to_ast
      assert_equal 1, Sync { client.search(ast, response_type: :results).wait }.total, connection.to_s
    ensure
      Sync { client.delete_index(INDEX).wait }
    end
  end
end
