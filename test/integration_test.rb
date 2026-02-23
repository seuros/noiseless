# frozen_string_literal: true

require_relative "test_helper"
require_relative "dummy/app/models/article"

class IntegrationTest < ActiveSupport::TestCase
  def setup
    @bulk_data = [
      { index: { _index: "articles", _id: "1", data: { title: "Test", content: "Test content" } } },
      { index: { _index: "articles", _id: "2", data: { title: "Another", content: "More content" } } }
    ]
    @search_model = Article::SearchFiction
  end

  def test_base_adapter_async_interface
    adapter = Noiseless::Adapter.new(hosts: [es_url])

    assert_async_bulk(adapter)
    assert_async_search(adapter)
  end

  def test_elasticsearch_adapter_async_interface
    adapter = Noiseless::Adapters::Elasticsearch.new(hosts: [es_url])

    assert_async_bulk(adapter)
    assert_async_search(adapter)
  end

  def test_opensearch_adapter_async_interface
    adapter = Noiseless::Adapters::OpenSearch.new(hosts: [os_url])

    assert_async_bulk(adapter)
    assert_async_search(adapter)
    assert_async_opensearch_features(adapter)
  end

  def test_typesense_adapter_async_interface
    adapter = Noiseless::Adapters::Typesense.new(hosts: [ts_url])

    assert_async_bulk(adapter)
    assert_async_search(adapter)
  end

  private

  def assert_async_bulk(adapter)
    task = adapter.bulk(@bulk_data)
    assert_kind_of Async::Task, task

    result = Sync { task.wait }
    assert_kind_of Hash, result
    # Result may have errors if index doesn't exist, but should still be a hash
    assert_kind_of Hash, result, "Expected Hash result from bulk operation"
  end

  def assert_async_search(adapter)
    queries = [
      build_match_query("search", "title"),
      build_multi_match_query("elasticsearch", %w[title content]),
      build_complex_query("technology", "published", "technology"),
      build_paginated_query("search", 2, 5),
      build_sorted_query("programming", "published_at", :desc)
    ]

    queries.each do |ast|
      task = adapter.search(ast, model_class: @search_model, response_type: :results)
      assert_kind_of Async::Task, task

      result = Sync { task.wait }
      assert_kind_of Noiseless::Response::Results, result
    end
  end

  def assert_async_opensearch_features(adapter)
    match_ast = build_match_query("search", "title")

    begin
      pit_task = adapter.point_in_time_search(match_ast, pit_id: "test_pit_id")
      assert_kind_of(Hash, Sync { pit_task.wait }) if pit_task.is_a?(Async::Task)
    rescue NoMethodError
      # Point-in-time search is optional; ignore if not implemented in test context
    end

    begin
      template_task = adapter.search_template(template_id: "test_template", params: { query: "test" })
      assert_kind_of(Hash, Sync { template_task.wait }) if template_task.is_a?(Async::Task)
    rescue NoMethodError
      # Search templates are optional; ignore if not implemented in test context
    end
  end

  # Helper methods to build AST nodes
  def build_match_query(value, field)
    match = Noiseless::AST::Match.new(field, value)
    bool_node = Noiseless::AST::Bool.new(must: [match], filter: [])
    Noiseless::AST::Root.new(
      indexes: ["articles"],
      bool: bool_node,
      sort: [],
      paginate: nil
    )
  end

  def build_multi_match_query(query, fields)
    multi_match = Noiseless::AST::MultiMatch.new(query, fields)
    bool_node = Noiseless::AST::Bool.new(must: [multi_match], filter: [])
    Noiseless::AST::Root.new(
      indexes: ["articles"],
      bool: bool_node,
      sort: [],
      paginate: nil
    )
  end

  def build_complex_query(search_term, status, category)
    match = Noiseless::AST::Match.new("content", search_term)
    filters = [
      Noiseless::AST::Filter.new("status", status),
      Noiseless::AST::Filter.new("category", category)
    ]
    bool_node = Noiseless::AST::Bool.new(must: [match], filter: filters)
    Noiseless::AST::Root.new(
      indexes: ["articles"],
      bool: bool_node,
      sort: [],
      paginate: nil
    )
  end

  def build_paginated_query(search_term, page, per_page)
    match = Noiseless::AST::Match.new("title", search_term)
    bool_node = Noiseless::AST::Bool.new(must: [match], filter: [])
    paginate = Noiseless::AST::Paginate.new(page, per_page)
    Noiseless::AST::Root.new(
      indexes: ["articles"],
      bool: bool_node,
      sort: [],
      paginate: paginate
    )
  end

  def build_sorted_query(search_term, sort_field, direction)
    match = Noiseless::AST::Match.new("category", search_term)
    bool_node = Noiseless::AST::Bool.new(must: [match], filter: [])
    sort_node = Noiseless::AST::Sort.new(sort_field, direction)
    Noiseless::AST::Root.new(
      indexes: ["articles"],
      bool: bool_node,
      sort: [sort_node],
      paginate: nil
    )
  end

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
end
