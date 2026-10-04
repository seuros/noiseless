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
      per_page: 20,
      enable_highlight_v1: false
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
      filter_by: "status:=`published` && category:=`tech`",
      sort_by: "created_at:desc,title:asc",
      page: 2,
      per_page: 25,
      enable_highlight_v1: false
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
      per_page: 20,
      enable_highlight_v1: false
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
      filter_by: "status:=`published`",
      page: 1,
      per_page: 20,
      enable_highlight_v1: false
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

  test "imports, searches, aggregates, updates and checks existence on a live collection" do
    collection = "noiseless_ts_live"
    model = Class.new(Noiseless::Model) { def self.name = "TypesenseLiveProbe" }
    Sync do
      @adapter.create_index(collection, mappings: { properties: { title: { type: "text" },
                                                                  status: { type: "keyword", facet: true } } }).wait
    end

    bulk = Sync do
      @adapter.bulk([
                      { index: { _index: collection, _id: 1, data: { title: "ruby search", status: "draft" } } },
                      { index: { _index: collection, _id: 2, data: { title: "ruby async", status: "live" } } }
                    ]).wait
    end
    assert_not bulk["errors"]

    Sync { @adapter.update_document(index: collection, id: 1, changes: { status: "live" }).wait }

    builder = Noiseless::QueryBuilder.new(model).indexes([collection]).match(:title, "ruby").filter(:status, "live")
    builder.aggregation(:by_status, :terms, field: :status)
    result = Sync { @adapter.search(builder.to_ast, response_type: :results).wait }

    assert_equal 2, result.total
    assert_equal [{ "key" => "live", "doc_count" => 2 }], result.aggregations["by_status"]["buckets"]
    assert(Sync { @adapter.index_exists?(collection).wait })
    assert(Sync { @adapter.document_exists?(index: collection, id: 1).wait })
    assert_not(Sync { @adapter.document_exists?(index: collection, id: 99).wait })

    Sync do
      @adapter.create_index("#{collection}_b", mappings: { properties: { title: { type: "text" } } }).wait
      @adapter.index_document(index: "#{collection}_b", id: 3, document: { title: "ruby union" }).wait
    end
    union = Noiseless::QueryBuilder.new(model).indexes([collection, "#{collection}_b"]).match(:title, "ruby")
    assert_equal 3, Sync { @adapter.search(union.to_ast, response_type: :results).wait }.total
  ensure
    Sync { [collection, "#{collection}_b"].each { @adapter.delete_index(it).wait } }
  end
end
