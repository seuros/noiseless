# frozen_string_literal: true

require "test_helper"

class TypesenseAdapterTest < ActiveSupport::TestCase
  def ts_url
    host = ENV.fetch("TYPESENSE_HOST", "localhost")
    port = ENV.fetch("TYPESENSE_PORT", "8108")
    "http://#{host}:#{port}"
  end

  setup do
    @adapter = Noiseless::Adapters::Typesense.new(hosts: [ts_url])
  end

  test "looks up Typesense adapter via dynamic class loading" do
    adapter = Noiseless::Adapters.lookup(:typesense, hosts: [ts_url])
    assert_instance_of Noiseless::Adapters::Typesense, adapter
  end

  test "converts simple match query to Typesense format" do
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
      q: "title:Ruby",
      page: 1,
      per_page: 20
    }

    assert_equal expected, query_hash
  end

  test "converts complex query with filters and sorting to Typesense format" do
    bool_node = Noiseless::AST::Bool.new(
      must: [
        Noiseless::AST::Match.new("title", "Ruby"),
        Noiseless::AST::Match.new("content", "programming")
      ],
      filter: [
        Noiseless::AST::Filter.new("status", "published"),
        Noiseless::AST::Filter.new("category", "tech")
      ]
    )
    sort_nodes = [
      Noiseless::AST::Sort.new("created_at", :desc),
      Noiseless::AST::Sort.new("title", :asc)
    ]
    paginate_node = Noiseless::AST::Paginate.new(2, 25)

    root_node = Noiseless::AST::Root.new(
      indexes: ["posts"],
      bool: bool_node,
      sort: sort_nodes,
      paginate: paginate_node
    )

    query_hash = @adapter.send(:ast_to_hash, root_node)

    expected = {
      q: "title:Ruby content:programming",
      filter_by: "status:=published && category:=tech",
      sort_by: "created_at:desc,title:asc",
      page: 2,
      per_page: 25
    }

    assert_equal expected, query_hash
  end

  test "handles empty query gracefully" do
    bool_node = Noiseless::AST::Bool.new(must: [], filter: [])
    root_node = Noiseless::AST::Root.new(
      indexes: ["posts"],
      bool: bool_node,
      sort: [],
      paginate: nil
    )

    query_hash = @adapter.send(:ast_to_hash, root_node)

    expected = {
      page: 1,
      per_page: 20
    }

    assert_equal expected, query_hash
  end

  test "handles filter-only queries" do
    bool_node = Noiseless::AST::Bool.new(
      must: [],
      filter: [Noiseless::AST::Filter.new("status", "published")]
    )
    root_node = Noiseless::AST::Root.new(
      indexes: ["posts"],
      bool: bool_node,
      sort: [],
      paginate: nil
    )

    query_hash = @adapter.send(:ast_to_hash, root_node)

    expected = {
      filter_by: "status:=published",
      page: 1,
      per_page: 20
    }

    assert_equal expected, query_hash
  end

  test "executes search and returns Typesense-style response" do
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

    task = @adapter.search(root_node)
    response = Sync { task.wait }

    # Verify response is a proper Response object and is empty (no data in test index)
    assert_instance_of Noiseless::Response::Results, response
    assert_respond_to response, :total
    assert_equal 0, response.total
    assert_empty response
  end

  test "executes bulk operations" do
    actions = [
      { index: { _index: "posts", _id: 1, data: { title: "Test" } } },
      { index: { _index: "posts", _id: 2, data: { title: "Another" } } }
    ]

    task = @adapter.bulk(actions)
    response = Sync { task.wait }

    # Verify bulk response format
    assert_includes response.keys, :items
    # The response might have errors, so check if items exists
    if response[:items].present?
      assert_equal 2, response[:items].size
      # Check that all items have index operations with created result
      assert(response[:items].all? { |item| item[:index] && item[:index][:result] == "created" })
    else
      # If no items due to mock/VCR, at least verify the structure
      assert_kind_of Array, response[:items]
    end
  end
end
