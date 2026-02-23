# frozen_string_literal: true

require "test_helper"

class MultiEngineTest < ActiveSupport::TestCase
  def es_url
    host = ENV.fetch("ELASTICSEARCH_HOST", "localhost")
    port = ENV.fetch("ELASTICSEARCH_PORT", "9200")
    "http://#{host}:#{port}"
  end

  def os_url
    host = ENV.fetch("OPENSEARCH_HOST", "localhost")
    port = ENV.fetch("OPENSEARCH_PORT", "9201")
    "http://#{host}:#{port}"
  end

  def ts_url
    host = ENV.fetch("TYPESENSE_HOST", "localhost")
    port = ENV.fetch("TYPESENSE_PORT", "8108")
    "http://#{host}:#{port}"
  end

  test "all three adapters can be instantiated" do
    elasticsearch = Noiseless::Adapters.lookup(:elasticsearch, hosts: [es_url])
    opensearch = Noiseless::Adapters.lookup(:open_search, hosts: [os_url])
    typesense = Noiseless::Adapters.lookup(:typesense, hosts: [ts_url])

    assert_instance_of Noiseless::Adapters::Elasticsearch, elasticsearch
    assert_instance_of Noiseless::Adapters::OpenSearch, opensearch
    assert_instance_of Noiseless::Adapters::Typesense, typesense
  end

  test "same AST produces different query formats for each adapter" do
    # Create a shared AST
    bool_node = Noiseless::AST::Bool.new(
      must: [Noiseless::AST::Match.new("title", "Ruby")],
      filter: [Noiseless::AST::Filter.new("status", "published")]
    )
    sort_nodes = [Noiseless::AST::Sort.new("created_at", :desc)]
    paginate_node = Noiseless::AST::Paginate.new(1, 10)

    root_node = Noiseless::AST::Root.new(
      indexes: ["posts"],
      bool: bool_node,
      sort: sort_nodes,
      paginate: paginate_node
    )

    # Test Elasticsearch format
    elasticsearch = Noiseless::Adapters::Elasticsearch.new(hosts: [es_url])
    es_query = elasticsearch.send(:ast_to_hash, root_node)

    assert_includes es_query.keys, :query
    assert_includes es_query[:query].keys, :bool
    assert_includes es_query[:query][:bool].keys, :must
    assert_includes es_query[:query][:bool].keys, :filter

    # Test OpenSearch format (should be similar to Elasticsearch)
    opensearch = Noiseless::Adapters::OpenSearch.new(hosts: [os_url])
    os_query = opensearch.send(:ast_to_hash, root_node)

    # OpenSearch should have same structure as Elasticsearch
    assert_equal es_query, os_query

    # Test Typesense format (should be completely different)
    typesense = Noiseless::Adapters::Typesense.new(hosts: [ts_url])
    ts_query = typesense.send(:ast_to_hash, root_node)

    assert_includes ts_query.keys, :q
    assert_includes ts_query.keys, :filter_by
    assert_includes ts_query.keys, :sort_by
    assert_equal "title:Ruby", ts_query[:q]
    assert_equal "status:=published", ts_query[:filter_by]
    assert_equal "created_at:desc", ts_query[:sort_by]

    # Verify they're all different formats
    assert_not_equal es_query, ts_query
    assert_not_equal os_query, ts_query
  end

  test "all adapters can execute search with same AST" do
    bool_node = Noiseless::AST::Bool.new(
      must: [Noiseless::AST::Match.new("title", "Ruby")],
      filter: []
    )
    root_node = Noiseless::AST::Root.new(
      indexes: ["posts"],
      bool: bool_node,
      sort: [],
      paginate: nil
    )

    # All adapters should be able to execute the same AST
    elasticsearch = Noiseless::Adapters::Elasticsearch.new(hosts: [es_url])
    opensearch = Noiseless::Adapters::OpenSearch.new(hosts: [os_url])
    typesense = Noiseless::Adapters::Typesense.new(hosts: [ts_url])

    # Search returns Async::Task, need to wait for results
    es_task = elasticsearch.search(root_node)
    os_task = opensearch.search(root_node)
    ts_task = typesense.search(root_node)

    # Wait for all tasks to complete
    es_response = Sync { es_task.wait }
    os_response = Sync { os_task.wait }
    ts_response = Sync { ts_task.wait }

    # Each should return a response (even if mocked)
    assert_not_nil es_response
    assert_not_nil os_response
    assert_not_nil ts_response

    # Elasticsearch/OpenSearch responses should be Response objects with proper methods
    assert_respond_to es_response, :total
    assert_respond_to os_response, :total

    # Typesense should also have Response object interface
    assert_respond_to ts_response, :total
  end

  test "connection manager loads all configured adapters" do
    # Verify all three connections are loaded from config
    primary = Noiseless.connections.client(:primary)
    opensearch = Noiseless.connections.client(:opensearch)
    typesense = Noiseless.connections.client(:typesense)

    assert_instance_of Noiseless::Adapters::Elasticsearch, primary
    assert_instance_of Noiseless::Adapters::OpenSearch, opensearch
    assert_instance_of Noiseless::Adapters::Typesense, typesense
  end
end
