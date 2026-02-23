# frozen_string_literal: true

require "test_helper"

class TypesenseFeaturesTest < ActiveSupport::TestCase
  def setup
    @model = Article::SearchFiction
    @test_embedding = [0.1, 0.2, 0.3]
  end

  # ============================================
  # Image Search Tests
  # ============================================

  def test_image_search_creates_ast_node
    builder = Noiseless::QueryBuilder.new(@model)
    builder.image_search(:image_embedding, "https://example.com/image.jpg")

    ast = builder.to_ast
    assert_predicate ast, :image_search?
    assert_equal "image_embedding", ast.image_query.field.to_s
    assert_equal "https://example.com/image.jpg", ast.image_query.image_data
  end

  def test_image_search_with_custom_k
    builder = Noiseless::QueryBuilder.new(@model)
    builder.image_search(:img, "https://example.com/photo.png", k: 25)

    ast = builder.to_ast
    assert_equal 25, ast.image_query.k
  end

  def test_image_search_url_detection
    builder = Noiseless::QueryBuilder.new(@model)
    builder.image_search(:img, "https://example.com/photo.png")

    ast = builder.to_ast
    assert_predicate ast.image_query, :url?
    assert_not_predicate ast.image_query, :base64?
  end

  def test_image_search_base64_detection
    builder = Noiseless::QueryBuilder.new(@model)
    builder.image_search(:img, "data:image/png;base64,iVBORw0KGgoAAAANS...")

    ast = builder.to_ast
    assert_not_predicate ast.image_query, :url?
    assert_predicate ast.image_query, :base64?
  end

  def test_typesense_image_search_query_hash
    adapter = Noiseless::Adapters::Typesense.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.image_search(:image_embedding, "https://example.com/image.jpg", k: 10)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert query_hash[:vector_query]
    assert_includes query_hash[:vector_query], "image_embedding"
    assert_includes query_hash[:vector_query], "https://example.com/image.jpg"
    assert_includes query_hash[:vector_query], "k:10"
  end

  # ============================================
  # Conversational/RAG Tests
  # ============================================

  def test_conversational_creates_ast_node
    builder = Noiseless::QueryBuilder.new(@model)
    builder.match(:content, "What is machine learning?")
           .conversational(model_id: "gpt-4")

    ast = builder.to_ast
    assert_predicate ast, :conversational?
    assert_equal "gpt-4", ast.conversation.model_id
  end

  def test_conversational_with_conversation_id
    builder = Noiseless::QueryBuilder.new(@model)
    builder.conversational(model_id: "claude-3", conversation_id: "conv_123")

    ast = builder.to_ast
    assert_predicate ast.conversation, :multi_turn?
    assert_equal "conv_123", ast.conversation.conversation_id
  end

  def test_conversational_with_system_prompt
    builder = Noiseless::QueryBuilder.new(@model)
    builder.conversational(model_id: "gpt-4", system_prompt: "You are a helpful assistant.")

    ast = builder.to_ast
    assert_predicate ast.conversation, :custom_prompt?
    assert_equal "You are a helpful assistant.", ast.conversation.system_prompt
  end

  def test_rag_alias
    builder = Noiseless::QueryBuilder.new(@model)
    builder.rag(model_id: "claude-3")

    ast = builder.to_ast
    assert_predicate ast, :conversational?
  end

  def test_typesense_conversational_query_hash
    adapter = Noiseless::Adapters::Typesense.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.match(:content, "query")
           .conversational(model_id: "gpt-4", conversation_id: "conv_123")

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert query_hash[:conversation]
    assert_equal "gpt-4", query_hash[:conversation_model_id]
    assert_equal "conv_123", query_hash[:conversation_id]
  end

  # ============================================
  # JOINs Tests
  # ============================================

  def test_join_creates_ast_node
    builder = Noiseless::QueryBuilder.new(@model)
    builder.join(:products, on: { product_id: :id }, include_fields: %i[name price])

    ast = builder.to_ast
    assert_predicate ast, :has_joins?
    assert_equal 1, ast.joins.size

    join = ast.joins.first
    assert_equal "products", join.collection
    assert_equal({ product_id: :id }, join.on)
    assert_equal %w[name price], join.include_fields
  end

  def test_multiple_joins
    builder = Noiseless::QueryBuilder.new(@model)
    builder.join(:products, on: { product_id: :id }, include_fields: [:name])
           .join(:categories, on: { category_id: :id }, include_fields: [:title])

    ast = builder.to_ast
    assert_equal 2, ast.joins.size
  end

  def test_join_strategy
    builder = Noiseless::QueryBuilder.new(@model)
    builder.join(:products, on: { product_id: :id }, strategy: :inner)

    ast = builder.to_ast
    assert_predicate ast.joins.first, :inner_join?
    assert_not_predicate ast.joins.first, :left_join?
  end

  def test_join_default_strategy_is_left
    builder = Noiseless::QueryBuilder.new(@model)
    builder.join(:products, on: { product_id: :id })

    ast = builder.to_ast
    assert_predicate ast.joins.first, :left_join?
  end

  def test_typesense_join_query_hash
    adapter = Noiseless::Adapters::Typesense.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.match(:title, "test")
           .join(:products, on: { product_id: :id }, include_fields: %i[name price])

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert query_hash[:include_fields]
    assert_includes query_hash[:include_fields], "$products(name, price)"
  end

  def test_typesense_multiple_joins_query_hash
    adapter = Noiseless::Adapters::Typesense.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.join(:products, on: {}, include_fields: [:name])
           .join(:categories, on: {}, include_fields: [:title])

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert_includes query_hash[:include_fields], "$products(name)"
    assert_includes query_hash[:include_fields], "$categories(title)"
  end

  def test_typesense_collapse_maps_group_max_candidates
    adapter = Noiseless::Adapters::Typesense.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.match(:title, "test")
           .collapse(:company_id, max_concurrent_group_searches: 250)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert_equal "company_id", query_hash[:group_by]
    assert_equal 1, query_hash[:group_limit]
    assert_equal 250, query_hash[:group_max_candidates]
  end

  def test_typesense_collapse_without_group_max_candidates
    adapter = Noiseless::Adapters::Typesense.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.match(:title, "test")
           .collapse(:company_id)

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert_equal "company_id", query_hash[:group_by]
    assert_equal 1, query_hash[:group_limit]
    assert_nil query_hash[:group_max_candidates]
  end

  def test_typesense_union_options_query_hash
    adapter = Noiseless::Adapters::Typesense.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.match(:title, "test")
           .remove_duplicates
           .facet_sample_slope(3.2)
           .pinned_hits({ "doc_10" => 1, "doc_25" => 2 })

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert_equal true, query_hash[:remove_duplicates]
    assert_equal 3.2, query_hash[:facet_sample_slope]
    assert_equal "doc_10:1,doc_25:2", query_hash[:pinned_hits]
  end

  # ============================================
  # Combined Features Tests
  # ============================================

  def test_vector_search_with_joins
    adapter = Noiseless::Adapters::Typesense.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.vector(:embedding, @test_embedding, k: 10)
           .join(:products, on: { product_id: :id }, include_fields: [:name])

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert query_hash[:vector_query]
    assert query_hash[:include_fields]
  end

  def test_hybrid_search_with_conversational
    adapter = Noiseless::Adapters::Typesense.new
    builder = Noiseless::QueryBuilder.new(@model)
    builder.hybrid("machine learning", @test_embedding, field: :embedding)
           .conversational(model_id: "gpt-4")

    query_hash = adapter.send(:ast_to_hash, builder.to_ast)

    assert query_hash[:q]
    assert query_hash[:vector_query]
    assert query_hash[:conversation]
  end
end
