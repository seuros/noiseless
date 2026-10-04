# frozen_string_literal: true

require_relative "test_helper"
require_relative "dummy/app/models/article"

class PgvectorSupportTest < ActiveSupport::TestCase
  HOSTILE = ["0.1]'::vector) AS x, (SELECT 1 FROM articles LIMIT 1)--"].freeze

  def setup
    skip "PostgreSQL not configured" unless postgresql_available?

    @adapter = Noiseless::Adapters::Postgresql.new
  end

  test "vector_search renders a float-only literal and rejects hostile elements" do
    @adapter.stub(:pgvector_available?, true) do
      sql = @adapter.vector_search(Article.all, ["0.1", 0.2], column: :title).to_sql
      assert_includes sql, %("title" <=> '[0.1,0.2]' AS vector_distance)

      assert_raises(ArgumentError) { @adapter.vector_search(Article.all, HOSTILE, column: :title) }
    end
  end

  test "knn, hybrid and store_embedding reject hostile input before building SQL" do
    @adapter.stub(:pgvector_available?, true) do
      assert_raises(ArgumentError) { @adapter.knn_search(Article, HOSTILE, column: :title) }
      assert_raises(ArgumentError) { @adapter.store_embedding(Article.new, HOSTILE) }
      assert_raises(ArgumentError) do
        @adapter.hybrid_search(Article.all, text_query: "x", embedding: HOSTILE, text_fields: [:title])
      end
      assert_raises(ArgumentError) do
        @adapter.hybrid_search(Article.all, text_query: "x", embedding: [0.1], text_fields: [:title],
                                            text_weight: "0.5) OR (1=1")
      end
    end
  end

  test "vector search returns nothing without pgvector instead of every row" do
    Article.create!(title: "t", content: "c", author: "a")

    @adapter.stub(:pgvector_available?, false) do
      assert_not @adapter.vector_search(Article.all, [0.1]).exists?
    end
  end

  test "vector search pages within the k nearest rows" do
    with_vector_table do |model|
      model.connection.execute(<<~SQL.squish)
        INSERT INTO vector_docs (label, "Embedding") VALUES
        ('a', '[1,0,0]'), ('b', '[0.9,0.1,0]'), ('c', '[0.5,0.5,0]'), ('d', '[0.1,1,0]'), ('e', '[0,0,1]')
      SQL

      root = Noiseless::AST::Root.new(
        indexes: ["vector_docs"],
        bool: Noiseless::AST::Bool.new(must: [], filter: []),
        sort: [],
        paginate: Noiseless::AST::Paginate.new(2, 3),
        vector: Noiseless::AST::Vector.new("Embedding", [1, 0, 0], k: 4)
      )
      result = @adapter.stub(:pgvector_available?, true) do
        Sync { @adapter.search(root, model_class: model, response_type: :results).wait }
      end

      assert_equal %w[d], result.records.pluck(:label)
      assert_equal 4, result.total
    end
  end

  test "hybrid search blends trigram and vector similarity by weight" do
    with_vector_table do |model|
      model.connection.execute(%(INSERT INTO vector_docs (label, "Embedding") VALUES ('ruby search', '[1,0,0]'), ('go async', '[0,1,0]')))

      ranked = lambda do |text_weight, vector_weight|
        vector = Noiseless::AST::Vector.new("Embedding", [0, 1, 0], k: 2)
        hybrid = Noiseless::AST::Hybrid.new("ruby", vector, fields: [:label], text_weight:, vector_weight:)
        root = Noiseless::AST::Root.new(indexes: ["vector_docs"], bool: Noiseless::AST::Bool.new(must: [], filter: []),
                                        sort: [], paginate: nil, hybrid:)
        @adapter.stub(:pgvector_available?, true) do
          Sync { @adapter.search(root, model_class: model, response_type: :results).wait }.records.pluck(:label)
        end
      end

      assert_equal ["ruby search", "go async"], ranked.call(0.9, 0.1)
      assert_equal ["go async", "ruby search"], ranked.call(0.1, 0.9)
    end
  end

  test "batch_store_embeddings writes through an integer primary key and quotes identifiers" do
    with_vector_table do |model|
      first, second = model.create!([{ label: "a" }, { label: "b" }])

      updated = @adapter.stub(:pgvector_available?, true) do
        @adapter.batch_store_embeddings(model, { first.id => [1, 0, 0], second.id => %w[0 1 0] }, column: "Embedding")
      end

      assert_equal 2, updated
      assert_equal [[first.id, "[1,0,0]"], [second.id, "[0,1,0]"]],
                   model.connection.select_rows(%(SELECT id, "Embedding"::text FROM vector_docs ORDER BY id))

      nearest = @adapter.stub(:pgvector_available?, true) do
        @adapter.vector_search(model.all, [0.9, 0.1, 0], column: "Embedding", limit: 1).to_a
      end
      assert_equal [first.id], nearest.map(&:id)
    end
  end

  test "batch_store_embeddings raises on hostile input instead of reporting zero" do
    with_vector_table do |model|
      record = model.create!(label: "a")

      @adapter.stub(:pgvector_available?, true) do
        assert_raises(ArgumentError) { @adapter.batch_store_embeddings(model, { record.id => HOSTILE }, column: "Embedding") }
      end
      assert_nil model.connection.select_value(%(SELECT "Embedding" FROM vector_docs))
    end
  end

  private

  # The column name is mixed case so an unquoted identifier would fail.
  def with_vector_table
    connection = ActiveRecord::Base.connection
    skip "pgvector not installable" unless connection.select_value("SELECT 1 FROM pg_available_extensions WHERE name = 'vector'")

    connection.execute("CREATE EXTENSION IF NOT EXISTS vector")
    vector_oid = connection.select_value("SELECT oid FROM pg_type WHERE typname = 'vector'").to_i
    connection.send(:type_map).register_type(vector_oid, ActiveRecord::Type::String.new)
    connection.execute(%(CREATE TABLE vector_docs (id bigserial PRIMARY KEY, label text, "Embedding" vector(3))))
    model = Class.new(ActiveRecord::Base) do
      self.table_name = "vector_docs"
      def self.name = "VectorDoc"
    end

    yield model
  end

  def postgresql_available?
    ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
  rescue StandardError
    false
  end
end
