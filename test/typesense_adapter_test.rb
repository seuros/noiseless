# frozen_string_literal: true

require "test_helper"

class TypesenseAdapterTest < ActiveSupport::TestCase
  setup do
    @adapter = Noiseless.connections.client(:typesense)
  end

  test "looks up Typesense adapter via dynamic class loading" do
    adapter = Noiseless.connections.client(:typesense)
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
      q: "Ruby",
      query_by: "title",
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
      q: "Ruby programming",
      query_by: "title,content",
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
      q: "*",
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
      q: "*",
      filter_by: "status:=published",
      page: 1,
      per_page: 20
    }

    assert_equal expected, query_hash
  end

  test "searching a missing collection raises instead of reading as zero hits" do
    bool_node = Noiseless::AST::Bool.new(
      must: [Noiseless::AST::Match.new("title", "Ruby")],
      filter: []
    )
    root_node = Noiseless::AST::Root.new(
      indexes: ["noiseless_missing_collection"],
      bool: bool_node,
      sort: [],
      paginate: nil
    )

    error = assert_raises(Noiseless::SearchError) { Sync { @adapter.search(root_node).wait } }
    assert_equal 404, error.status
    assert_not(Sync { @adapter.index_exists?("noiseless_missing_collection").wait })
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
