# frozen_string_literal: true

module Benchmark
  class Loader
    def self.article_mappings
      {
        properties: {
          title: { type: "text" },
          content: { type: "text" },
          author: { type: "keyword" },
          category: { type: "keyword" },
          status: { type: "keyword" },
          tags: { type: "keyword" },
          published_at: { type: "date" },
          view_count: { type: "integer" }
        }
      }
    end

    def self.load_postgresql
      Rails.logger.tagged("LOAD") { Rails.logger.info "Loading PostgreSQL..." }
      start = Time.now

      Article.delete_all
      fixtures_path = Rails.root.join("../../test/fixtures")
      ActiveRecord::FixtureSet.create_fixtures(fixtures_path, ["articles"])

      duration = Time.now - start
      count = Article.count
      Rails.logger.info "PostgreSQL: #{count} records loaded in #{duration.round(2)}s"

      # Register model with PostgreSQL adapter
      Noiseless.connections.client(:postgresql).register_model(Article, index_name: "articles")
    end

    def self.load_search_engine(engine_name, adapter_key)
      Rails.logger.tagged("INDEX") { Rails.logger.info "Loading #{engine_name}..." }
      start = Time.now

      Sync do
        client = Noiseless.connections.client(adapter_key)

        # Delete and create index
        begin
          client.delete_index("articles").wait
        rescue StandardError
          # Index might not exist
        end

        client.create_index("articles", mappings: article_mappings).wait

        # Bulk index in batches
        Article.find_in_batches(batch_size: 1000) do |batch|
          actions = batch.map do |article|
            {
              index: {
                _index: "articles",
                _id: article.id,
                data: article.to_search_hash
              }
            }
          end

          client.bulk(actions, refresh: false).wait
        end

        # Refresh index
        client.indices.refresh(index: "articles")
      end

      duration = Time.now - start
      Rails.logger.info "#{engine_name}: #{Article.count} records indexed in #{duration.round(2)}s"
    end

    def self.data_exists?
      Article.exists?
    end
  end
end
