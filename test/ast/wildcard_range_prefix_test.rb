# frozen_string_literal: true

require "test_helper"

class Company < ApplicationSearch; end

class WildcardRangePrefixTest < Minitest::Test
  def test_wildcard_ast_node_creation
    wildcard = Noiseless::AST::Wildcard.new("name", "*test*")
    assert_equal "name", wildcard.field
    assert_equal "*test*", wildcard.value
  end

  def test_wildcard_ast_node_to_h
    wildcard = Noiseless::AST::Wildcard.new("description", "test*")
    hash = wildcard.to_h
    assert_equal "description", hash[:field]
    assert_equal "test*", hash[:value]
  end

  def test_range_ast_node_creation
    range = Noiseless::AST::Range.new("created_at", gte: "2024-01-01", lte: "2024-12-31")
    assert_equal "created_at", range.field
    assert_equal "2024-01-01", range.gte
    assert_equal "2024-12-31", range.lte
    assert_nil range.gt
    assert_nil range.lt
  end

  def test_range_ast_node_with_gt_lt
    range = Noiseless::AST::Range.new("count", gt: 10, lt: 100)
    assert_equal "count", range.field
    assert_equal 10, range.gt
    assert_equal 100, range.lt
    assert_nil range.gte
    assert_nil range.lte
  end

  def test_range_ast_node_to_h
    range = Noiseless::AST::Range.new("price", gte: 100, lte: 500)
    hash = range.to_h
    assert_equal "price", hash[:field]
    assert_equal 100, hash[:gte]
    assert_equal 500, hash[:lte]
  end

  def test_prefix_ast_node_creation
    prefix = Noiseless::AST::Prefix.new("category", "eco")
    assert_equal "category", prefix.field
    assert_equal "eco", prefix.value
  end

  def test_prefix_ast_node_to_h
    prefix = Noiseless::AST::Prefix.new("slug", "prod-")
    hash = prefix.to_h
    assert_equal "slug", hash[:field]
    assert_equal "prod-", hash[:value]
  end

  def test_bool_node_with_should
    must_node = Noiseless::AST::Match.new("status", "active")
    should_node = Noiseless::AST::Wildcard.new("name", "*eco*")
    filter_node = Noiseless::AST::Filter.new("deleted", false)

    bool = Noiseless::AST::Bool.new(must: [must_node], should: [should_node], filter: [filter_node])
    assert_equal 1, bool.must.length
    assert_equal 1, bool.should.length
    assert_equal 1, bool.filter.length
  end

  def test_query_builder_with_wildcard
    builder = Noiseless::QueryBuilder.new(Company)
    builder.wildcard("name", "*test*")

    ast = builder.to_ast
    assert ast.bool.must.any?(Noiseless::AST::Wildcard)
  end

  def test_query_builder_with_range
    builder = Noiseless::QueryBuilder.new(Company)
    builder.range("created_at", gte: "2024-01-01", lte: "2024-12-31")

    ast = builder.to_ast
    assert ast.bool.must.any?(Noiseless::AST::Range)
  end

  def test_query_builder_with_prefix
    builder = Noiseless::QueryBuilder.new(Company)
    builder.prefix("slug", "eco-")

    ast = builder.to_ast
    assert ast.bool.must.any?(Noiseless::AST::Prefix)
  end

  def test_query_builder_wildcard_to_hash
    builder = Noiseless::QueryBuilder.new(Company)
    builder.wildcard("name", "*test*").paginate(page: 1, per_page: 10)

    ast = builder.to_ast
    adapter = Noiseless::Adapter.new
    hash = adapter.send(:ast_to_hash, ast)

    assert_includes hash[:query][:bool][:must].map(&:keys).flatten, :wildcard
  end

  def test_query_builder_range_to_hash
    builder = Noiseless::QueryBuilder.new(Company)
    builder.range("price", gte: 100, lte: 500).paginate(page: 1, per_page: 10)

    ast = builder.to_ast
    adapter = Noiseless::Adapter.new
    hash = adapter.send(:ast_to_hash, ast)

    assert_includes hash[:query][:bool][:must].map(&:keys).flatten, :range
  end

  def test_query_builder_prefix_to_hash
    builder = Noiseless::QueryBuilder.new(Company)
    builder.prefix("category", "eco").paginate(page: 1, per_page: 10)

    ast = builder.to_ast
    adapter = Noiseless::Adapter.new
    hash = adapter.send(:ast_to_hash, ast)

    assert_includes hash[:query][:bool][:must].map(&:keys).flatten, :prefix
  end

  def test_adapter_builds_wildcard_query
    adapter = Noiseless::Adapter.new
    wildcard = Noiseless::AST::Wildcard.new("description", "*sustainable*")
    bool = Noiseless::AST::Bool.new(must: [wildcard])

    query = adapter.send(:build_query_hash, bool)
    wildcard_query = query[:bool][:must].find { |q| q.key?(:wildcard) }
    assert_predicate wildcard_query, :present?, "No wildcard query found in #{query[:bool][:must].inspect}"
    assert_equal "*sustainable*", wildcard_query[:wildcard]["description"]
  end

  def test_adapter_builds_range_query
    adapter = Noiseless::Adapter.new
    range = Noiseless::AST::Range.new("established_year", gte: 2000, lte: 2020)
    bool = Noiseless::AST::Bool.new(must: [range])

    query = adapter.send(:build_query_hash, bool)
    range_query_hash = query[:bool][:must].find { |q| q.key?(:range) }
    assert_predicate range_query_hash, :present?, "No range query found in #{query[:bool][:must].inspect}"
    range_query = range_query_hash[:range]["established_year"]
    assert_equal 2000, range_query[:gte]
    assert_equal 2020, range_query[:lte]
  end

  def test_adapter_builds_prefix_query
    adapter = Noiseless::Adapter.new
    prefix = Noiseless::AST::Prefix.new("slug", "comp-")
    bool = Noiseless::AST::Bool.new(must: [prefix])

    query = adapter.send(:build_query_hash, bool)
    assert(query[:bool][:must].any? { |q| q.key?(:prefix) })
    prefix_query = query[:bool][:must].find { |q| q.key?(:prefix) }
    assert_predicate prefix_query, :present?, "No prefix query found in #{query[:bool][:must].inspect}"
    assert_equal "comp-", prefix_query[:prefix]["slug"]
  end

  def test_adapter_builds_multiple_must_queries
    adapter = Noiseless::Adapter.new
    wildcard = Noiseless::AST::Wildcard.new("name", "*eco*")
    match = Noiseless::AST::Match.new("category", "sustainable")
    bool = Noiseless::AST::Bool.new(must: [match, wildcard])

    query = adapter.send(:build_query_hash, bool)
    assert_equal 2, query[:bool][:must].length
  end

  def test_combined_query_with_all_types
    builder = Noiseless::QueryBuilder.new(Company)
    builder
      .match("status", "active")
      .wildcard("name", "*test*")
      .range("employees", gte: 10, lte: 1000)
      .prefix("category", "eco")
      .filter("deleted", false)
      .paginate(page: 1, per_page: 25)

    ast = builder.to_ast
    adapter = Noiseless::Adapter.new
    hash = adapter.send(:ast_to_hash, ast)

    # Verify structure
    assert hash[:query][:bool]
    assert_equal 25, hash[:size]
    assert_equal 0, hash[:from]
  end

  def test_wildcard_patterns
    adapter = Noiseless::Adapter.new

    # Test *value* pattern
    wildcard1 = Noiseless::AST::Wildcard.new("name", "*test*")
    bool1 = Noiseless::AST::Bool.new(must: [wildcard1])
    query1 = adapter.send(:build_query_hash, bool1)
    wildcard_result1 = query1[:bool][:must].find { |q| q.key?(:wildcard) }
    assert_predicate wildcard_result1, :present?, "No wildcard query found in #{query1[:bool][:must].inspect}"
    found1 = wildcard_result1[:wildcard]["name"]
    assert_equal "*test*", found1

    # Test value* pattern
    wildcard2 = Noiseless::AST::Wildcard.new("name", "test*")
    bool2 = Noiseless::AST::Bool.new(must: [wildcard2])
    query2 = adapter.send(:build_query_hash, bool2)
    wildcard_result2 = query2[:bool][:must].find { |q| q.key?(:wildcard) }
    assert_predicate wildcard_result2, :present?, "No wildcard query found in #{query2[:bool][:must].inspect}"
    found2 = wildcard_result2[:wildcard]["name"]
    assert_equal "test*", found2

    # Test *value pattern
    wildcard3 = Noiseless::AST::Wildcard.new("name", "*test")
    bool3 = Noiseless::AST::Bool.new(must: [wildcard3])
    query3 = adapter.send(:build_query_hash, bool3)
    wildcard_result3 = query3[:bool][:must].find { |q| q.key?(:wildcard) }
    assert_predicate wildcard_result3, :present?, "No wildcard query found in #{query3[:bool][:must].inspect}"
    found3 = wildcard_result3[:wildcard]["name"]
    assert_equal "*test", found3
  end

  def test_range_with_only_gte
    adapter = Noiseless::Adapter.new
    range = Noiseless::AST::Range.new("created_at", gte: "2024-01-01")
    bool = Noiseless::AST::Bool.new(must: [range])

    query = adapter.send(:build_query_hash, bool)
    range_query_hash = query[:bool][:must].find { |q| q.key?(:range) }
    assert_predicate range_query_hash, :present?, "No range query found in #{query[:bool][:must].inspect}"
    range_query = range_query_hash[:range]["created_at"]
    assert_equal "2024-01-01", range_query[:gte]
    assert_nil range_query[:lte]
  end

  def test_range_with_only_lt
    adapter = Noiseless::Adapter.new
    range = Noiseless::AST::Range.new("score", lt: 100)
    bool = Noiseless::AST::Bool.new(must: [range])

    query = adapter.send(:build_query_hash, bool)
    range_query_hash = query[:bool][:must].find { |q| q.key?(:range) }
    assert_predicate range_query_hash, :present?, "No range query found in #{query[:bool][:must].inspect}"
    range_query = range_query_hash[:range]["score"]
    assert_equal 100, range_query[:lt]
    assert_nil range_query[:gte]
    assert_nil range_query[:lte]
  end

  def test_empty_bool_returns_empty_hash
    adapter = Noiseless::Adapter.new
    bool = Noiseless::AST::Bool.new(must: [], filter: [], should: [])

    query = adapter.send(:build_query_hash, bool)
    assert_empty query
  end

  def test_multiple_wildcard_queries
    adapter = Noiseless::Adapter.new
    w1 = Noiseless::AST::Wildcard.new("name", "*eco*")
    w2 = Noiseless::AST::Wildcard.new("description", "*sustainable*")
    bool = Noiseless::AST::Bool.new(must: [w1, w2])

    query = adapter.send(:build_query_hash, bool)
    assert_equal 2, query[:bool][:must].length
    assert(query[:bool][:must].all? { |q| q.key?(:wildcard) })
  end
end
