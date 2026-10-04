# frozen_string_literal: true

require "test_helper"

class BulkImporterTest < ActiveSupport::TestCase
  INDEX = "noiseless_reindex_probe"

  class Probe < Noiseless::Model
    def self.name = "BulkImporterTest::Probe"

    search_index INDEX
    connection :opensearch
    mapping { properties { status :keyword } }
  end

  teardown { Sync { client.delete_index(INDEX).wait } }

  test "force import recreates the mapped index and documents are searchable at once" do
    importer = Noiseless::BulkImporter.new(Probe)
    importer.import([{ id: 1, status: "stale" }])
    result = importer.import([{ id: 2, status: "fresh" }], force: true)

    assert_equal 0, result[:errors]
    assert_equal("keyword", Sync { mapping_type("status") })
    assert_equal 1, Sync { client.search_raw({ query: { match_all: {} } }, indexes: [INDEX]).wait }
      .dig("hits", "total", "value")
  end

  private

  def client = Noiseless.connections.client(:opensearch)

  def mapping_type(field)
    response = client.send(:get_request, "/#{INDEX}/_mapping")
    JSON.parse(response.read).dig(INDEX, "mappings", "properties", field, "type")
  ensure
    response&.close
  end
end
