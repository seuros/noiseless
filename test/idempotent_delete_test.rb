# frozen_string_literal: true

require_relative "test_helper"

class IdempotentDeleteTest < ActiveSupport::TestCase
  MISSING_INDEX = "noiseless_idempotent_delete_missing"

  def test_elasticsearch_delete_missing_index_does_not_raise
    Sync do
      result = Noiseless.connections.client(:primary).delete_index(MISSING_INDEX).wait

      assert_equal "not_found", result["result"]
      assert result["acknowledged"]
    end
  end

  def test_opensearch_delete_missing_index_does_not_raise
    Sync do
      result = os_adapter.delete_index(MISSING_INDEX).wait

      assert_equal "not_found", result["result"]
      assert result["acknowledged"]
    end
  end

  def test_elasticsearch_delete_missing_document_does_not_raise
    Sync do
      result = Noiseless.connections.client(:primary).delete_document(index: MISSING_INDEX, id: "nope").wait

      assert_equal "not_found", result["result"]
      assert_equal MISSING_INDEX, result["_index"]
      assert_equal "nope", result["_id"]
    end
  end

  def test_opensearch_delete_missing_document_does_not_raise
    Sync do
      result = os_adapter.delete_document(index: MISSING_INDEX, id: "nope").wait

      assert_equal "not_found", result["result"]
      assert_equal MISSING_INDEX, result["_index"]
      assert_equal "nope", result["_id"]
    end
  end

  def test_opensearch_delete_existing_document_still_reports_deleted
    Sync do
      adapter = os_adapter
      adapter.index_document(index: MISSING_INDEX, id: "1", document: { title: "t" }).wait

      result = adapter.delete_document(index: MISSING_INDEX, id: "1").wait

      assert_equal "deleted", result["result"]
    ensure
      adapter.delete_index(MISSING_INDEX).wait
    end
  end

  def test_refresh_index_is_public_and_async_wrapped
    Sync do
      adapter = os_adapter
      adapter.index_document(index: MISSING_INDEX, id: "1", document: { title: "t" }).wait

      result = adapter.refresh_index(MISSING_INDEX).wait

      assert result["_shards"]
    ensure
      adapter.delete_index(MISSING_INDEX).wait
    end
  end

  def test_refresh_index_works_without_surrounding_reactor
    Sync { os_adapter.create_index("noiseless_refresh_no_reactor").wait }

    assert os_adapter.refresh_index("noiseless_refresh_no_reactor").wait["_shards"]
  ensure
    Sync { os_adapter.delete_index("noiseless_refresh_no_reactor").wait }
  end

  private

  def os_adapter
    Noiseless.connections.client(:opensearch)
  end
end
