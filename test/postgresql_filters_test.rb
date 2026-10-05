# frozen_string_literal: true

require "test_helper"

class PostgresqlFiltersTest < PostgresqlSearchCase
  test "array column filters use contains/overlap semantics and work through search" do
    supplier, agent, buyer = Article.first(3)
    supplier.update!(roles: %w[supplier buyer])
    agent.update!(roles: %w[agent])
    buyer.update!(roles: %w[buyer])

    term = @adapter.send(
      :apply_filter_clauses, Article.all, [Noiseless::AST::Filter.new(:roles, "supplier")], Article
    )
    assert_includes term.to_sql, "@>"
    assert_equal [supplier.id], term.pluck(:id)

    terms = @adapter.send(
      :apply_filter_clauses, Article.all,
      [Noiseless::AST::Filter.new(:roles, %w[supplier agent])], Article
    )
    assert_includes terms.to_sql, "&&"
    assert_equal [supplier.id, agent.id].sort, terms.pluck(:id).sort

    builder = Noiseless::QueryBuilder.new(@search_model)
    builder.where(:roles, "agent")
    result = Sync do
      @adapter.search(builder.to_ast, model_class: Article, response_type: :results).wait
    end
    assert_equal 1, result.total
  end

  test "wildcard, range and prefix fail closed on ghost fields but match real columns" do
    ghost_scopes = [
      @adapter.send(:apply_wildcard, Article.all,
                    Noiseless::AST::Wildcard.new(:ghost_field, "*x*"), Article),
      @adapter.send(:apply_range, Article.all,
                    Noiseless::AST::Range.new(:ghost_field, gte: 1), Article),
      @adapter.send(:apply_prefix, Article.all,
                    Noiseless::AST::Prefix.new(:ghost_field, "x"), Article)
    ]
    ghost_scopes.each do |scope|
      assert_empty scope.to_a, "Ghost-field clause must fail closed, not raise or broaden"
    end

    builder = Noiseless::QueryBuilder.new(@search_model)
    builder.wildcard(:title, "*Part*")
    result = Sync do
      @adapter.search(builder.to_ast, model_class: Article, response_type: :results).wait
    end
    assert result.total.positive?
  end

  test "range-shaped filters build a range predicate like ES/OpenSearch" do
    threshold = Article.average(:view_count).to_i
    builder = Noiseless::QueryBuilder.new(@search_model)
    builder.filter(:view_count, { "gte" => threshold })
    result = Sync do
      @adapter.search(builder.to_ast, model_class: Article, response_type: :results).wait
    end

    assert_equal Article.where(view_count: threshold..).count, result.total
  end

  test "filters work for a model on a non-PostgreSQL connection" do
    model = Class.new(ActiveRecord::Base) do
      self.table_name = "docs"
      def self.name = "SqliteDoc"
    end
    model.establish_connection(adapter: "sqlite3", database: ":memory:")
    model.connection.create_table(:docs) { |t| t.string :status }
    model.create!([{ status: "open" }, { status: "closed" }])

    scope = @adapter.send(
      :apply_filter_clauses, model.all, [Noiseless::AST::Filter.new(:status, "open")], model
    )
    assert_equal ["open"], scope.pluck(:status)
  ensure
    model&.remove_connection
  end

  test "geo filter quotes the column and accepts symbol or string keyed points" do
    [
      { geo_distance: { distance: "10km", title: { lat: 48.85, lon: 2.35 } } },
      { "geo_distance" => { "distance" => "10km", "title" => { "lat" => "48.85", "lon" => "2.35" } } }
    ].each do |value|
      sql = @adapter.send(
        :apply_filter_clauses, Article.all, [Noiseless::AST::Filter.new(:title, value)], Article
      ).to_sql

      assert_includes sql, %(ST_DWithin("title"::geography, ST_SetSRID(ST_MakePoint(2.35, 48.85), 4326)::geography, 10000.0))
    end
  end

  test "geo filter fails closed on ghost fields and injected field names" do
    ["ghost_location", "title) OR 1=1 --"].each do |field|
      node = Noiseless::AST::Filter.new(field, { geo_distance: { distance: "10km", field => { lat: 1, lon: 2 } } })
      scope = @adapter.send(:apply_filter_clauses, Article.all, [node], Article)

      assert_not scope.exists?, "#{field.inspect} must not broaden results"
      assert_not_includes scope.to_sql, "OR 1=1"
    end

    node = Noiseless::AST::Filter.new("title) OR 1=1 --", { geo_distance: { distance: "1km", x: { lat: 1, lon: 2 } } })
    assert_includes @adapter.send(:apply_geo_filter, Article.all, node).to_sql,
                    '"title) OR 1=1 --"::geography',
                    "Without a model the field must still be quoted as an identifier"
  end

  test "geo filter with a missing or malformed point fails closed" do
    assert Article.exists?, "Fixtures must be loaded for this test to mean anything"

    [
      { geo_distance: { distance: "10km" } },
      { geo_distance: { distance: "10km", title: { lat: nil, lon: 2.35 } } },
      { geo_distance: { distance: "10km", title: { lat: "north", lon: 2.35 } } },
      { geo_distance: "10km" }
    ].each do |value|
      scope = @adapter.send(
        :apply_filter_clauses, Article.all, [Noiseless::AST::Filter.new(:title, value)], Article
      )
      assert_not scope.exists?, "Expected #{value.inspect} to fail closed"
    end
  end
end
