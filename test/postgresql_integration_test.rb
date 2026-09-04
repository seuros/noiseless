# frozen_string_literal: true

require_relative "test_helper"
require_relative "dummy/app/models/article"

class PostgresqlIntegrationTest < ActiveSupport::TestCase
  fixtures :articles

  def setup
    skip "PostgreSQL not configured" unless postgresql_available?

    @adapter = Noiseless::Adapters::Postgresql.new
    @search_model = Article::SearchFiction
    @adapter.register_model(Article, index_name: "articles")
  end

  def teardown
    Article.delete_all if postgresql_available?
  end

  test "searches articles using PostgreSQL full-text search" do
    builder = Noiseless::QueryBuilder.new(@search_model)
    # Search for a term that exists in fixture titles (e.g., "Part")
    builder.match(:title, "Part")
    ast = builder.to_ast

    result = Sync do
      @adapter.search(ast, model_class: Article, response_type: :results).wait
    end

    assert_kind_of Noiseless::Response::Results, result
    assert result.total.positive?, 'Expected to find articles matching "Part"'
  end

  test "filters articles by status" do
    builder = Noiseless::QueryBuilder.new(@search_model)
    builder.where(:status, "published")
    ast = builder.to_ast

    result = Sync do
      @adapter.search(ast, model_class: Article, response_type: :results).wait
    end

    assert_kind_of Noiseless::Response::Results, result
    result.records.each do |record|
      assert_equal "published", record["status"]
    end
  end

  test "paginates results" do
    builder = Noiseless::QueryBuilder.new(@search_model)
    builder.paginate(page: 1, per_page: 2)
    ast = builder.to_ast

    result = Sync do
      @adapter.search(ast, model_class: Article, response_type: :results).wait
    end

    assert_operator result.records.size, :<=, 2
  end

  test "sorts results by field" do
    builder = Noiseless::QueryBuilder.new(@search_model)
    builder.order(:published_at, :desc)
    builder.where(:status, "published")
    ast = builder.to_ast

    result = Sync do
      @adapter.search(ast, model_class: Article, response_type: :results).wait
    end

    dates = result.records.map { |r| r["published_at"] }.compact
    assert_equal dates, dates.sort.reverse, "Expected results sorted by published_at desc"
  end

  test "cluster health returns green status" do
    health = @adapter.cluster.health

    assert_equal "postgresql", health["cluster_name"]
    assert_includes %w[green yellow], health["status"]
  end

  test "detects available extensions" do
    extensions = @adapter.available_extensions

    assert_kind_of Array, extensions
    # At minimum, we expect pg_trgm for text search
    assert_includes extensions, "pg_trgm", "Expected pg_trgm extension to be available"
  end

  test "handles empty search results" do
    builder = Noiseless::QueryBuilder.new(@search_model)
    builder.match(:title, "NonexistentQueryString12345")
    ast = builder.to_ast

    result = Sync do
      @adapter.search(ast, model_class: Article, response_type: :results).wait
    end

    assert_equal 0, result.total
    assert_empty result.records
  end

  test "total reflects unpaginated match count, not the page size" do
    builder = Noiseless::QueryBuilder.new(@search_model)
    builder.paginate(page: 1, per_page: 2)
    ast = builder.to_ast

    result = Sync do
      @adapter.search(ast, model_class: Article, response_type: :results).wait
    end

    assert_operator result.records.size, :<=, 2
    assert_equal Article.count, result.total
  end

  test "multi_match drops mapping-only fields and still matches on real columns" do
    builder = Noiseless::QueryBuilder.new(@search_model)
    builder.multi_match("Bluetooth", %i[title name_aliases])
    ast = builder.to_ast

    result = Sync do
      @adapter.search(ast, model_class: Article, response_type: :results).wait
    end

    assert result.total.positive?, "Expected matches on title despite unknown name_aliases field"
  end

  test "multi_match with only mapping-only fields fails closed" do
    builder = Noiseless::QueryBuilder.new(@search_model)
    builder.multi_match("Bluetooth", %i[name_aliases other_ghost_field])
    ast = builder.to_ast

    result = Sync do
      @adapter.search(ast, model_class: Article, response_type: :results).wait
    end

    assert_equal 0, result.total
  end

  test "match on a mapping-only field fails closed" do
    builder = Noiseless::QueryBuilder.new(@search_model)
    builder.match(:name_aliases, "Bluetooth")
    ast = builder.to_ast

    result = Sync do
      @adapter.search(ast, model_class: Article, response_type: :results).wait
    end

    assert_equal 0, result.total
  end

  test "filter on a mapping-only field fails closed" do
    builder = Noiseless::QueryBuilder.new(@search_model)
    builder.where(:ghost_field, "anything")
    ast = builder.to_ast

    result = Sync do
      @adapter.search(ast, model_class: Article, response_type: :results).wait
    end

    assert_equal 0, result.total
  end

  test "sort on a mapping-only field is dropped instead of erroring" do
    builder = Noiseless::QueryBuilder.new(@search_model)
    builder.order(:ghost_field, :desc)
    builder.where(:status, "published")
    ast = builder.to_ast

    result = Sync do
      @adapter.search(ast, model_class: Article, response_type: :results).wait
    end

    assert result.total.positive?
  end

  test "records support indifferent access for pluck(:id) finder patterns" do
    builder = Noiseless::QueryBuilder.new(@search_model)
    builder.match(:title, "Part")
    ast = builder.to_ast

    result = Sync do
      @adapter.search(ast, model_class: Article, response_type: :results).wait
    end

    ids = result.records.pluck(:id)
    assert ids.any?, "Expected records"
    assert ids.all?(Integer), "pluck(:id) must return real ids, got: #{ids.first(3).inspect}"
    assert_equal ids, result.records.pluck("id")
  end

  test "document writes are no-ops and never mutate source rows" do
    article = Article.first
    original_title = article.title

    index_result = Sync do
      @adapter.index_document(
        index: "articles", id: article.id, document: { "title" => "MUTATED BY INDEXER" }
      ).wait
    end
    assert_equal "noop", index_result["result"]

    delete_result = Sync do
      @adapter.delete_document(index: "articles", id: article.id).wait
    end
    assert_equal "noop", delete_result["result"]

    assert_equal original_title, article.reload.title
    assert Article.exists?(article.id), "delete_document must not destroy source rows"
  end

  private

  def postgresql_available?
    # Check if we're running against PostgreSQL
    ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
  rescue StandardError
    false
  end
end
