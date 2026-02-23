# frozen_string_literal: true

require "test_helper"

class PostgresqlAdapterTest < ActiveSupport::TestCase
  def setup
    @adapter = Noiseless::Adapters::Postgresql.new(skip_extension_check: true)
  end

  test "can be loaded via adapters lookup" do
    adapter = Noiseless::Adapters.lookup(:postgresql, skip_extension_check: true)
    assert_instance_of Noiseless::Adapters::Postgresql, adapter
  end

  test "async_context? returns false" do
    assert_not @adapter.async_context?
  end

  test "cluster health returns green status when database is connected" do
    health = @adapter.cluster.health
    assert_equal "postgresql", health["cluster_name"]
    assert_includes %w[green yellow], health["status"]
  end

  test "indices API returns empty stats" do
    stats = @adapter.indices.stats(index: "test_index")
    assert_kind_of Hash, stats
    assert stats.key?("indices")
  end

  test "indices refresh is a no-op" do
    result = @adapter.indices.refresh(index: "test_index")
    assert_equal 1, result.dig("_shards", "successful")
  end

  test "ast_to_hash includes all query components" do
    # Create a simple AST
    bool_node = Noiseless::AST::Bool.new(must: [], filter: [])
    paginate_node = Noiseless::AST::Paginate.new(1, 20)
    root = Noiseless::AST::Root.new(
      indexes: ["products"],
      bool: bool_node,
      sort: [],
      paginate: paginate_node
    )

    query_hash = @adapter.send(:ast_to_hash, root)

    assert_equal ["products"], query_hash[:indexes]
    assert_equal bool_node, query_hash[:bool]
    assert_equal paginate_node, query_hash[:paginate]
    assert_nil query_hash[:vector]
  end

  test "ast_to_hash includes vector node when present" do
    bool_node = Noiseless::AST::Bool.new(must: [], filter: [])
    vector_node = Noiseless::AST::Vector.new(:embedding, [0.1, 0.2, 0.3], k: 5)
    root = Noiseless::AST::Root.new(
      indexes: ["products"],
      bool: bool_node,
      sort: [],
      paginate: nil,
      vector: vector_node
    )

    query_hash = @adapter.send(:ast_to_hash, root)

    assert_equal vector_node, query_hash[:vector]
  end
end

class PostgresqlExecutionTest < ActiveSupport::TestCase
  # Test the execution module methods
  class MockModel
    def self.table_name
      "mock_models"
    end

    def self.all
      MockRelation.new
    end

    def self.column_names
      %w[id name description]
    end

    def self.columns_hash
      {
        "id" => OpenStruct.new(type: :uuid),
        "name" => OpenStruct.new(type: :string),
        "description" => OpenStruct.new(type: :text)
      }
    end

    def self.where(*)
      MockRelation.new
    end

    def self.exists?(*)
      true
    end

    def self.count
      10
    end

    def self.table_exists?
      true
    end
  end

  class MockRelation
    def where(*)
      self
    end

    def order(*)
      self
    end

    def limit(*)
      self
    end

    def offset(*)
      self
    end

    def to_a
      []
    end
  end

  def setup
    @adapter = Noiseless::Adapters::Postgresql.new(skip_extension_check: true)
    @adapter.register_model(MockModel, index_name: "mock_models")
  end

  test "register_model caches the model" do
    assert_equal MockModel, @adapter.model_class_cache["mock_models"]
  end

  test "empty response has correct structure" do
    response = @adapter.send(:empty_response)

    assert_equal 0, response.dig("hits", "total", "value")
    assert_empty response.dig("hits", "hits")
    assert_equal "eq", response.dig("hits", "total", "relation")
  end

  test "error response includes error details" do
    error = StandardError.new("Test error")
    response = @adapter.send(:error_response, error)

    assert_equal "StandardError", response.dig("error", "type")
    assert_equal "Test error", response.dig("error", "reason")
    assert_equal 0, response.dig("hits", "total", "value")
  end
end

class VectorAstNodeTest < ActiveSupport::TestCase
  test "creates vector node with defaults" do
    node = Noiseless::AST::Vector.new(:embedding, [0.1, 0.2, 0.3])

    assert_equal :embedding, node.field
    assert_equal [0.1, 0.2, 0.3], node.embedding
    assert_equal 10, node.k
    assert_equal :cosine, node.distance_metric
  end

  test "creates vector node with custom parameters" do
    node = Noiseless::AST::Vector.new(
      :content_vector,
      [0.5] * 1536,
      k: 20,
      distance_metric: :l2
    )

    assert_equal :content_vector, node.field
    assert_equal 1536, node.dimension
    assert_equal 20, node.k
    assert_equal :l2, node.distance_metric
  end

  test "dimension returns embedding size" do
    node = Noiseless::AST::Vector.new(:embedding, [0.1] * 768)
    assert_equal 768, node.dimension
  end

  test "dimension returns 0 for nil embedding" do
    node = Noiseless::AST::Vector.new(:embedding, nil)
    assert_equal 0, node.dimension
  end
end

class QueryBuilderVectorTest < ActiveSupport::TestCase
  class MockSearchModel
    def self.search_index
      ["mock_search"]
    end
  end

  test "vector method adds vector node" do
    builder = Noiseless::QueryBuilder.new(MockSearchModel)
    embedding = [0.1, 0.2, 0.3]

    builder.vector(:embedding, embedding)
    ast = builder.to_ast

    assert_predicate ast, :vector_search?
    assert_instance_of Noiseless::AST::Vector, ast.vector
    assert_equal embedding, ast.vector.embedding
  end

  test "knn is aliased to vector" do
    builder = Noiseless::QueryBuilder.new(MockSearchModel)

    builder.knn(:embedding, [0.1, 0.2])
    ast = builder.to_ast

    assert_predicate ast, :vector_search?
  end

  test "semantic_search is aliased to vector" do
    builder = Noiseless::QueryBuilder.new(MockSearchModel)

    builder.semantic_search(:embedding, [0.1, 0.2])
    ast = builder.to_ast

    assert_predicate ast, :vector_search?
  end

  test "vector with custom options" do
    builder = Noiseless::QueryBuilder.new(MockSearchModel)

    builder.vector(:content_embedding, [0.5] * 100, k: 50, distance_metric: :inner_product)
    ast = builder.to_ast

    assert_equal 50, ast.vector.k
    assert_equal :inner_product, ast.vector.distance_metric
  end

  test "only first vector node is included in AST" do
    builder = Noiseless::QueryBuilder.new(MockSearchModel)

    builder.vector(:embedding1, [0.1])
    builder.vector(:embedding2, [0.2])
    ast = builder.to_ast

    assert_equal :embedding1, ast.vector.field
  end
end

class RootAstVectorTest < ActiveSupport::TestCase
  test "vector_search? returns false when no vector" do
    bool_node = Noiseless::AST::Bool.new(must: [], filter: [])
    root = Noiseless::AST::Root.new(
      indexes: ["test"],
      bool: bool_node,
      sort: [],
      paginate: nil
    )

    assert_not root.vector_search?
  end

  test "vector_search? returns true when vector present" do
    bool_node = Noiseless::AST::Bool.new(must: [], filter: [])
    vector_node = Noiseless::AST::Vector.new(:embedding, [0.1])
    root = Noiseless::AST::Root.new(
      indexes: ["test"],
      bool: bool_node,
      sort: [],
      paginate: nil,
      vector: vector_node
    )

    assert_predicate root, :vector_search?
  end
end
