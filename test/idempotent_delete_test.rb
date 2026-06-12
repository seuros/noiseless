# frozen_string_literal: true

require_relative "test_helper"

class IdempotentDeleteTest < ActiveSupport::TestCase
  MISSING_INDEX = "noiseless_idempotent_delete_missing"

  def test_elasticsearch_delete_missing_index_does_not_raise
    Sync do
      result = adapter_for(es_url).delete_index(MISSING_INDEX).wait

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
      result = adapter_for(es_url).delete_document(index: MISSING_INDEX, id: "nope").wait

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
    # Calling outside a reactor must not raise "No async task available!"
    error = assert_raises(Noiseless::RequestError) do
      os_adapter.refresh_index("noiseless_refresh_no_reactor").wait
    end

    assert_match(/index_not_found/, error.message)
  end

  private

  def adapter_for(url)
    Noiseless::Adapters::Elasticsearch.new(hosts: [url])
  end

  def os_adapter
    Noiseless::Adapters::OpenSearch.new(hosts: [os_url])
  end

  def es_url
    host = ENV.fetch("ELASTICSEARCH_HOST", "localhost")
    port = ENV.fetch("ELASTICSEARCH_PORT", "9201")
    "http://#{host}:#{port}"
  end

  def os_url
    host = ENV.fetch("OPENSEARCH_HOST", "localhost")
    port = ENV.fetch("OPENSEARCH_PORT", "9202")
    "http://#{host}:#{port}"
  end
end
