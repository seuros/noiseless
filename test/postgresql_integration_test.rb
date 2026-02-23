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

  private

  def postgresql_available?
    # Check if we're running against PostgreSQL
    ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
  rescue StandardError
    false
  end
end
