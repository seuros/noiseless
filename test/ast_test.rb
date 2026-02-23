# frozen_string_literal: true

require "test_helper"

class ASTTest < ActiveSupport::TestCase
  test "creates Match nodes" do
    node = Noiseless::AST::Match.new("title", "Ruby")
    assert_equal "title", node.field
    assert_equal "Ruby", node.value
  end

  test "creates Filter nodes" do
    node = Noiseless::AST::Filter.new("status", "active")
    assert_equal "status", node.field
    assert_equal "active", node.value
  end

  test "creates Sort nodes" do
    node = Noiseless::AST::Sort.new("created_at", :desc)
    assert_equal "created_at", node.field
    assert_equal :desc, node.direction
  end

  test "creates Paginate nodes" do
    node = Noiseless::AST::Paginate.new(2, 50)
    assert_equal 2, node.page
    assert_equal 50, node.per_page
  end

  test "creates Bool nodes" do
    must_nodes = [Noiseless::AST::Match.new("title", "Ruby")]
    filter_nodes = [Noiseless::AST::Filter.new("status", "active")]

    node = Noiseless::AST::Bool.new(must: must_nodes, filter: filter_nodes)
    assert_equal must_nodes, node.must
    assert_equal filter_nodes, node.filter
  end

  test "creates Root nodes" do
    bool_node = Noiseless::AST::Bool.new
    sort_nodes = [Noiseless::AST::Sort.new("created_at", :desc)]
    paginate_node = Noiseless::AST::Paginate.new(1, 20)

    node = Noiseless::AST::Root.new(
      indexes: ["posts"],
      bool: bool_node,
      sort: sort_nodes,
      paginate: paginate_node
    )

    assert_equal ["posts"], node.indexes
    assert_equal bool_node, node.bool
    assert_equal sort_nodes, node.sort
    assert_equal paginate_node, node.paginate
  end
end
