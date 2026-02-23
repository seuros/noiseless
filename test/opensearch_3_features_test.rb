# frozen_string_literal: true

require "test_helper"

class OpenSearch3FeaturesTest < ActiveSupport::TestCase
  def setup
    @model = Article::SearchFiction
  end

  # ============================================
  # Field Collapsing Tests
  # ============================================

  def test_collapse_creates_ast_node
    builder = Noiseless::QueryBuilder.new(@model)
    builder.match(:title, "test").collapse(:company_id)

    ast = builder.to_ast
    assert_predicate ast, :collapsed?
    assert_equal "company_id", ast.collapse.field
  end

  def test_collapse_with_inner_hits
    builder = Noiseless::QueryBuilder.new(@model)
    builder.collapse(:company_id, inner_hits: { name: "top_hits", size: 3 })

    ast = builder.to_ast
    assert_equal({ name: "top_hits", size: 3 }, ast.collapse.inner_hits)
  end

  def test_collapse_generates_correct_query_hash
    adapter = Noiseless::Adapters::OpenSearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.match(:title, "test").collapse(:company_id)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert_equal({ field: "company_id" }, query_hash[:collapse])
  end

  # ============================================
  # search_after Tests
  # ============================================

  def test_search_after_creates_ast_node
    builder = Noiseless::QueryBuilder.new(@model)
    builder.sort(:created_at, :desc).search_after([1_699_900_000, "doc_123"])

    ast = builder.to_ast
    assert_predicate ast, :cursor_pagination?
    assert_equal [1_699_900_000, "doc_123"], ast.search_after.values
  end

  def test_search_after_replaces_offset_pagination
    adapter = Noiseless::Adapters::OpenSearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.sort(:created_at, :desc)
           .paginate(page: 1, per_page: 25)
           .search_after([1_699_900_000, "doc_123"])

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert_equal [1_699_900_000, "doc_123"], query_hash[:search_after]
    assert_equal 25, query_hash[:size]
    assert_nil query_hash[:from] # No offset when using search_after
  end

  # ============================================
  # Combined Fields Tests
  # ============================================

  def test_combined_fields_creates_ast_node
    builder = Noiseless::QueryBuilder.new(@model)
    builder.combined_fields("search query", %i[title description content])

    ast = builder.to_ast
    must_nodes = ast.bool.must
    assert_equal 1, must_nodes.size
    assert_instance_of Noiseless::AST::CombinedFields, must_nodes.first
    assert_equal "search query", must_nodes.first.query
    assert_equal %w[title description content], must_nodes.first.fields
  end

  def test_combined_fields_with_options
    builder = Noiseless::QueryBuilder.new(@model)
    builder.combined_fields("search", %i[title body], operator: "and", minimum_should_match: "75%")

    ast = builder.to_ast
    node = ast.bool.must.first
    assert_equal({ operator: "and", minimum_should_match: "75%" }, node.options)
  end

  def test_combined_fields_generates_correct_query_hash
    adapter = Noiseless::Adapters::OpenSearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.combined_fields("test query", %w[title description], operator: "and")

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    expected_must = {
      combined_fields: {
        query: "test query",
        fields: %w[title description],
        operator: "and"
      }
    }
    assert_equal expected_must, query_hash[:query][:bool][:must].first
  end

  # ============================================
  # Aggregations Tests
  # ============================================

  def test_metric_aggregation_creates_ast_node
    builder = Noiseless::QueryBuilder.new(@model)
    builder.agg(:avg_price, :avg, field: :price)

    ast = builder.to_ast
    assert_predicate ast, :aggregated?
    assert_equal 1, ast.aggregations.size

    agg = ast.aggregations.first
    assert_equal "avg_price", agg.name
    assert_equal :avg, agg.type
    assert_equal "price", agg.field
    assert_predicate agg, :metric?
  end

  def test_bucket_aggregation_creates_ast_node
    builder = Noiseless::QueryBuilder.new(@model)
    builder.agg(:by_category, :terms, field: :category, size: 10)

    ast = builder.to_ast
    agg = ast.aggregations.first
    assert_equal :terms, agg.type
    assert_equal({ size: 10 }, agg.options)
    assert_predicate agg, :bucket?
  end

  def test_nested_aggregations
    builder = Noiseless::QueryBuilder.new(@model)
    builder.agg(:by_category, :terms, field: :category) do
      agg(:avg_price, :avg, field: :price)
      agg(:max_price, :max, field: :price)
    end

    ast = builder.to_ast
    parent_agg = ast.aggregations.first
    assert_equal 2, parent_agg.sub_aggregations.size
    assert_equal "avg_price", parent_agg.sub_aggregations[0].name
    assert_equal "max_price", parent_agg.sub_aggregations[1].name
  end

  def test_aggregation_generates_correct_query_hash
    adapter = Noiseless::Adapters::OpenSearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.agg(:by_category, :terms, field: :category, size: 10)
           .agg(:avg_price, :avg, field: :price)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    expected_aggs = {
      "by_category" => { terms: { field: "category", size: 10 } },
      "avg_price" => { avg: { field: "price" } }
    }
    assert_equal expected_aggs, query_hash[:aggs]
  end

  def test_nested_aggregation_generates_correct_query_hash
    adapter = Noiseless::Adapters::OpenSearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.agg(:by_category, :terms, field: :category) do
      agg(:avg_price, :avg, field: :price)
    end

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    expected = {
      "by_category" => {
        terms: { field: "category" },
        aggs: {
          "avg_price" => { avg: { field: "price" } }
        }
      }
    }
    assert_equal expected, query_hash[:aggs]
  end

  # ============================================
  # Combined Features Test
  # ============================================

  def test_combined_features_query
    adapter = Noiseless::Adapters::OpenSearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.combined_fields("laptop", %w[name description])
           .filter(:status, "active")
           .sort(:created_at, :desc)
           .collapse(:brand)
           .agg(:by_brand, :terms, field: :brand, size: 5)
           .paginate(per_page: 20)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    # Verify all components are present
    assert(query_hash[:query][:bool][:must].any? { |m| m[:combined_fields] })
    assert(query_hash[:query][:bool][:filter].any? { |f| f[:term][:status] == "active" })
    assert_equal [{ created_at: { order: :desc } }], query_hash[:sort]
    assert_equal({ field: "brand" }, query_hash[:collapse])
    assert query_hash[:aggs]["by_brand"]
    assert_equal 20, query_hash[:size]
  end
end
