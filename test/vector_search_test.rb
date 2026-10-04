# frozen_string_literal: true

require "test_helper"

class VectorSearchTest < ActiveSupport::TestCase
  def setup
    @model = Article::SearchFiction
    # Sample 3-dimensional embedding for testing
    @test_embedding = [0.1, 0.2, 0.3]
  end

  # ============================================
  # AST Node Tests
  # ============================================

  def test_vector_creates_ast_node
    builder = Noiseless::QueryBuilder.new(@model)
    builder.vector(:embedding, @test_embedding)

    ast = builder.to_ast
    assert_predicate ast, :vector_search?
    assert_equal "embedding", ast.vector.field.to_s
    assert_equal @test_embedding, ast.vector.embedding
    assert_equal 10, ast.vector.k # default
    assert_equal :cosine, ast.vector.distance_metric # default
  end

  def test_vector_with_custom_k
    builder = Noiseless::QueryBuilder.new(@model)
    builder.vector(:embedding, @test_embedding, k: 25)

    ast = builder.to_ast
    assert_equal 25, ast.vector.k
  end

  def test_vector_with_distance_metric
    builder = Noiseless::QueryBuilder.new(@model)
    builder.vector(:embedding, @test_embedding, distance_metric: :l2)

    ast = builder.to_ast
    assert_equal :l2, ast.vector.distance_metric
  end

  def test_knn_alias
    builder = Noiseless::QueryBuilder.new(@model)
    builder.knn(:embedding, @test_embedding, k: 5)

    ast = builder.to_ast
    assert_predicate ast, :vector_search?
    assert_equal 5, ast.vector.k
  end

  def test_semantic_search_alias
    builder = Noiseless::QueryBuilder.new(@model)
    builder.semantic_search(:embedding, @test_embedding, k: 15)

    ast = builder.to_ast
    assert_predicate ast, :vector_search?
    assert_equal 15, ast.vector.k
  end

  def test_vector_dimension
    builder = Noiseless::QueryBuilder.new(@model)
    builder.vector(:embedding, @test_embedding)

    ast = builder.to_ast
    assert_equal 3, ast.vector.dimension
  end

  # ============================================
  # OpenSearch kNN Query Generation
  # ============================================

  def test_opensearch_knn_with_filters
    adapter = Noiseless::Adapters::OpenSearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.vector(:embedding, @test_embedding, k: 5)
           .filter(:status, "published")

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    knn = query_hash.dig(:query, :knn, "embedding")
    assert_equal @test_embedding, knn[:vector]
    assert_equal 5, knn[:k]
    assert_equal [{ term: { status: "published" } }], knn.dig(:filter, :bool, :filter)
    assert_equal({ excludes: ["embedding"] }, query_hash[:_source])
  end

  # ============================================
  # Elasticsearch kNN Query Generation
  # ============================================

  def test_elasticsearch_knn_query_hash
    adapter = Noiseless::Adapters::Elasticsearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.vector(:embedding, @test_embedding, k: 10)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert query_hash[:knn], "kNN query should be present"
    assert_equal "embedding", query_hash[:knn][:field]
    assert_equal [@test_embedding.pack("g*")].pack("m0"), query_hash[:knn][:query_vector]
    assert_equal 10, query_hash[:knn][:k]
  end

  # ============================================
  # Typesense Vector Query Generation
  # ============================================

  def test_typesense_vector_query_hash
    adapter = Noiseless::Adapters::Typesense.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.vector(:embedding, @test_embedding, k: 10)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert query_hash[:vector_query], "vector_query should be present"
    expected_query = "embedding:([0.1,0.2,0.3], k:10)"
    assert_equal expected_query, query_hash[:vector_query]
  end

  def test_typesense_vector_query_with_different_k
    adapter = Noiseless::Adapters::Typesense.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.vector(:vec_field, [1.0, 2.0, 3.0, 4.0], k: 25)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    expected_query = "vec_field:([1.0,2.0,3.0,4.0], k:25)"
    assert_equal expected_query, query_hash[:vector_query]
  end

  # ============================================
  # Combined Vector + Text Search
  # ============================================

  def test_vector_with_text_query
    adapter = Noiseless::Adapters::OpenSearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.match(:title, "machine learning")
           .vector(:embedding, @test_embedding, k: 10)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    must = query_hash.dig(:query, :bool, :must)
    assert_equal "machine learning", must.first[:match][:title]
    assert must.last.dig(:knn, "embedding")
  end

  def test_vector_with_pagination
    adapter = Noiseless::Adapters::OpenSearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.vector(:embedding, @test_embedding, k: 20)
           .paginate(page: 2, per_page: 10)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert query_hash.dig(:query, :knn, "embedding")
    assert_equal 10, query_hash[:from]
    assert_equal 10, query_hash[:size]
  end

  def test_vector_with_sort
    adapter = Noiseless::Adapters::OpenSearch.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.vector(:embedding, @test_embedding)
           .sort(:_score, :desc)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert query_hash.dig(:query, :knn, "embedding")
    assert_equal [{ _score: { order: :desc } }], query_hash[:sort]
  end
end
