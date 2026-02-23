# frozen_string_literal: true

namespace :benchmark do
  desc "Benchmark search performance across Elasticsearch, OpenSearch, and PostgreSQL"
  task search: :environment do
    require "benchmark/ips"
    require "async"

    # Use configured connections from Rails
    engines = {
      elasticsearch: :primary,
      opensearch: :secondary,
      postgresql: :postgresql
    }

    puts "=" * 80
    puts "MULTI-ENGINE SEARCH BENCHMARK"
    puts "=" * 80
    puts "Records: 10k benchmark articles"
    puts "Engines: #{engines.keys.join(', ')}"
    puts "=" * 80

    # Load PostgreSQL data
    puts "\n📊 Loading PostgreSQL..."
    Article.delete_all
    fixtures_path = Rails.root.join("../../test/fixtures")
    ActiveRecord::FixtureSet.create_fixtures(fixtures_path, ["benchmark_articles"])
    puts "✅ Loaded #{Article.count} records"

    # Register PostgreSQL model
    Noiseless.connections.client(:postgresql).register_model(Article, index_name: "articles")

    puts "\n🚀 Benchmark ready. Run with: bundle exec rake benchmark:search"
  end
end
