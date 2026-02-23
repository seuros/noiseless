# frozen_string_literal: true

require "test_helper"

class HybridSearchTest < ActiveSupport::TestCase
  def setup
    @model = Article::SearchFiction
    @test_embedding = [0.1, 0.2, 0.3]
  end

  # ============================================
  # AST Node Tests
  # ============================================

  def test_hybrid_creates_ast_node
    builder = Noiseless::QueryBuilder.new(@model)
    builder.hybrid("machine learning", @test_embedding, field: :embedding)

    ast = builder.to_ast
    assert_predicate ast, :hybrid_search?
    assert_equal "machine learning", ast.hybrid.text_query
    assert_equal @test_embedding, ast.hybrid.vector.embedding
    assert_equal "embedding", ast.hybrid.vector.field.to_s
  end

  def test_hybrid_with_custom_weights
    builder = Noiseless::QueryBuilder.new(@model)
    builder.hybrid("test query", @test_embedding, field: :vec, text_weight: 0.7, vector_weight: 0.3)

    ast = builder.to_ast
    assert_in_delta(0.7, ast.hybrid.text_weight)
    assert_in_delta(0.3, ast.hybrid.vector_weight)
    assert_predicate ast.hybrid, :text_dominant?
    assert_not_predicate ast.hybrid, :vector_dominant?
    assert_not_predicate ast.hybrid, :balanced?
  end

  def test_hybrid_with_custom_k
    builder = Noiseless::QueryBuilder.new(@model)
    builder.hybrid("query", @test_embedding, field: :embedding, k: 50)

    ast = builder.to_ast
    assert_equal 50, ast.hybrid.vector.k
  end

  def test_hybrid_default_weights_are_balanced
    builder = Noiseless::QueryBuilder.new(@model)
    builder.hybrid("query", @test_embedding, field: :embedding)

    ast = builder.to_ast
    assert_predicate ast.hybrid, :balanced?
    assert_in_delta(0.5, ast.hybrid.text_weight)
    assert_in_delta(0.5, ast.hybrid.vector_weight)
  end

  def test_vector_dominant_hybrid
    builder = Noiseless::QueryBuilder.new(@model)
    builder.hybrid("query", @test_embedding, field: :vec, text_weight: 0.2, vector_weight: 0.8)

    ast = builder.to_ast
    assert_predicate ast.hybrid, :vector_dominant?
    assert_not_predicate ast.hybrid, :text_dominant?
  end

  # ============================================
  # OpenSearch Hybrid Query Generation
  # ============================================

  def test_opensearch_hybrid_query_hash
    adapter = Noiseless::Adapters::OpenSearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.hybrid("machine learning", @test_embedding, field: :embedding, k: 10)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    # Should have query, knn, and rank (RRF)
    assert query_hash[:query], "Query should be present"
    assert query_hash[:knn], "kNN should be present"
    assert query_hash[:rank], "Rank (RRF) should be present"
    assert_equal "machine learning", query_hash[:query][:bool][:should].first[:match][:_all]
    assert_equal @test_embedding, query_hash[:knn][:query_vector]
    assert query_hash[:rank][:rrf]
  end

  def test_opensearch_hybrid_rrf_window_size
    adapter = Noiseless::Adapters::OpenSearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.hybrid("query", @test_embedding, field: :embedding, k: 25)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    # Window size should be k * 2
    assert_equal 50, query_hash[:rank][:rrf][:window_size]
  end

  # ============================================
  # Elasticsearch Hybrid Query Generation
  # ============================================

  def test_elasticsearch_hybrid_query_hash
    adapter = Noiseless::Adapters::Elasticsearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.hybrid("search term", @test_embedding, field: :vec)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert query_hash[:query]
    assert query_hash[:knn]
    assert query_hash[:rank][:rrf]
  end

  # ============================================
  # Typesense Hybrid Query Generation
  # ============================================

  def test_typesense_hybrid_query_hash
    adapter = Noiseless::Adapters::Typesense.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.hybrid("search query", @test_embedding, field: :embedding, k: 10, vector_weight: 0.6)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    # Typesense uses q + vector_query with alpha parameter
    assert_equal "search query", query_hash[:q]
    assert_includes query_hash[:vector_query], "embedding"
    assert_includes query_hash[:vector_query], "alpha:0.6"
    assert_includes query_hash[:vector_query], "k:10"
  end

  # ============================================
  # Pipeline Tests (OpenSearch only)
  # ============================================

  def test_pipeline_creates_ast_node
    builder = Noiseless::QueryBuilder.new(@model)
    builder.match(:title, "test").pipeline("my_reranking_pipeline")

    ast = builder.to_ast
    assert_predicate ast, :has_pipeline?
    assert_equal "my_reranking_pipeline", ast.pipeline
  end

  def test_opensearch_pipeline_in_query_hash
    adapter = Noiseless::Adapters::OpenSearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.match(:title, "test").pipeline("neural_reranker")

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert_equal "neural_reranker", query_hash[:search_pipeline]
  end

  # ============================================
  # Combined Features
  # ============================================

  def test_hybrid_with_filters
    adapter = Noiseless::Adapters::OpenSearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.hybrid("laptop", @test_embedding, field: :embedding)
           .filter(:category, "electronics")
           .paginate(page: 1, per_page: 20)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert query_hash[:knn]
    assert query_hash[:rank][:rrf]
    assert_equal 0, query_hash[:from]
    assert_equal 20, query_hash[:size]
  end
end
