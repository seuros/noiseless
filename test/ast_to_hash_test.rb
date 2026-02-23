# frozen_string_literal: true

require "test_helper"

class AstToHashTest < ActiveSupport::TestCase
  def es_url
    host = ENV.fetch("ELASTICSEARCH_HOST", "localhost")
    port = ENV.fetch("ELASTICSEARCH_PORT", "9200")
    "http://#{host}:#{port}"
  end

  setup do
    @adapter = Noiseless::Adapters::Elasticsearch.new(hosts: [es_url])
  end

  test "converts simple match query to hash" do
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

    query_hash = @adapter.send(:ast_to_hash, root_node)

    expected = {
      query: {
        bool: {
          must: [{ match: { "title" => "Ruby" } }]
        }
      },
      from: 0,
      size: 20
    }

    assert_equal expected, query_hash
  end

  test "converts complex query with sort and pagination to hash" do
    bool_node = Noiseless::AST::Bool.new(
      must: [Noiseless::AST::Match.new("title", "Ruby")],
      filter: [Noiseless::AST::Filter.new("status", "published")]
    )
    sort_nodes = [Noiseless::AST::Sort.new("created_at", :desc)]
    paginate_node = Noiseless::AST::Paginate.new(2, 25)

    root_node = Noiseless::AST::Root.new(
      indexes: ["posts"],
      bool: bool_node,
      sort: sort_nodes,
      paginate: paginate_node
    )

    query_hash = @adapter.send(:ast_to_hash, root_node)

    expected = {
      query: {
        bool: {
          must: [{ match: { "title" => "Ruby" } }],
          filter: [{ term: { "status" => "published" } }]
        }
      },
      sort: [{ "created_at" => { order: :desc } }],
      from: 25,
      size: 25
    }

    assert_equal expected, query_hash
  end

  test "handles empty query" do
    bool_node = Noiseless::AST::Bool.new(must: [], filter: [])
    root_node = Noiseless::AST::Root.new(
      indexes: ["posts"],
      bool: bool_node,
      sort: [],
      paginate: nil
    )

    query_hash = @adapter.send(:ast_to_hash, root_node)

    expected = {
      from: 0,
      size: 20
    }

    assert_equal expected, query_hash
  end
end
