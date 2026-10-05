# frozen_string_literal: true

class PostgresqlSearchCase < ActiveSupport::TestCase
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

  private

  def postgresql_available?
    ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
  rescue StandardError
    false
  end
end
