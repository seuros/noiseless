#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "benchmark/ips"

# Load Rails test environment
ENV["RAILS_ENV"] = "test"
require_relative "../test/test_helper"

require "async"

# Service hosts from environment
ES_HOST = ENV.fetch("ELASTICSEARCH_HOST", "localhost")
ES_PORT = ENV.fetch("ELASTICSEARCH_PORT", "9200")
OS_HOST = ENV.fetch("OPENSEARCH_HOST", "localhost")
OS_PORT = ENV.fetch("OPENSEARCH_PORT", "9201")

# Configure Noiseless connections
Noiseless.configure do |config|
  config.connections_config = {
    primary: {
      adapter: :elasticsearch,
      hosts: ["http://#{ES_HOST}:#{ES_PORT}"]
    },
    secondary: {
      adapter: :open_search,
      hosts: ["http://#{OS_HOST}:#{OS_PORT}"]
    },
    postgresql: {
      adapter: :postgresql
    }
  }
end

# Register connections
Noiseless.connections.register(:primary, adapter: :elasticsearch, hosts: ["http://#{ES_HOST}:#{ES_PORT}"])
Noiseless.connections.register(:secondary, adapter: :open_search, hosts: ["http://#{OS_HOST}:#{OS_PORT}"])
# PostgreSQL uses ActiveRecord connection directly, no hosts needed
Noiseless.connections.register(:postgresql, adapter: :postgresql, hosts: [])

# Configuration
RECORD_COUNT = ENV.fetch("BENCHMARK_RECORDS", 10_000).to_i
WARMUP_TIME = ENV.fetch("WARMUP_TIME", 2).to_i
BENCHMARK_TIME = ENV.fetch("BENCHMARK_TIME", 5).to_i

# Connection aliases
ENGINES = {
  elasticsearch: :primary,
  opensearch: :secondary,
  postgresql: :postgresql
}.freeze

puts "=" * 80
puts "MULTI-ENGINE SEARCH BENCHMARK"
puts "=" * 80
puts "Records: #{RECORD_COUNT}"
puts "Engines: #{ENGINES.keys.join(', ')}"
puts "=" * 80

# Data loading functions
def load_postgresql_data
  puts "\n📊 Loading data into PostgreSQL..."
  start = Time.now

  # Clean existing data
  Article.delete_all

  # Load fixtures using ActiveRecord::FixtureSet
  fixtures_path = File.expand_path("../test/fixtures", __dir__)
  ActiveRecord::FixtureSet.create_fixtures(fixtures_path, ["benchmark_articles"])

  duration = Time.now - start
  count = Article.count
  puts "✅ PostgreSQL: #{count} records loaded in #{duration.round(2)}s"

  # Register model with PostgreSQL adapter
  pg_adapter = Noiseless.connections.client(:postgresql)
  pg_adapter.register_model(Article, index_name: "articles")
end

def article_mappings
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

def load_search_engine_data(engine_name, adapter_key)
  puts "\n🔍 Loading data into #{engine_name}..."
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
    client.indices.refresh(index: "articles").wait
  end

  duration = Time.now - start
  puts "✅ #{engine_name}: #{Article.count} records indexed in #{duration.round(2)}s"
end

# Query modules
module SimpleQueries
  QUERIES = [
    {
      name: "Match title",
      query: ->(model) { model.match(:title, "interface") }
    },
    {
      name: "Filter category",
      query: ->(model) { model.filter(:category, "technology") }
    },
    {
      name: "Range view_count",
      query: ->(model) { model.range(:view_count, gte: 1000) }
    }
  ].freeze

  def self.random
    QUERIES.sample(random: Random.new(Time.now.to_i))
  end
end

module MediumQueries
  QUERIES = [
    {
      name: "Match + filter + paginate",
      query: lambda { |model|
        model.match(:content, "aut")
             .filter(:status, "published")
             .paginate(page: 10, per_page: 20)
      }
    },
    {
      name: "Multi-match + range + sort",
      query: lambda { |model|
        model.multi_match("quae", %i[title content])
             .range(:published_at, gte: 180.days.ago)
             .sort(:view_count, :desc)
             .limit(50)
      }
    },
    {
      name: "Filter + filter + paginate",
      query: lambda { |model|
        model.filter(:category, "programming")
             .filter(:status, "published")
             .paginate(page: 50, per_page: 20)
      }
    }
  ].freeze

  def self.random
    QUERIES.sample(random: Random.new(Time.now.to_i))
  end
end

module ComplexQueries
  QUERIES = [
    {
      name: "Match + filters + agg + sort",
      query: lambda { |model|
        model.match(:content, "aut")
             .filter(:status, "published")
             .filter(:category, "technology")
             .range(:view_count, gte: 100)
             .aggregation(:categories, :terms, field: :category, size: 10)
             .sort(:published_at, :desc)
             .paginate(page: 5, per_page: 20)
      }
    },
    {
      name: "Multi-match + multi-filter + agg",
      query: lambda { |model|
        model.multi_match("interface", %i[title content])
             .filter(:status, "published")
             .range(:published_at, gte: 180.days.ago)
             .aggregation(:top_authors, :terms, field: :author, size: 10)
             .sort(:view_count, :desc)
             .limit(100)
      }
    }
  ].freeze

  def self.random
    QUERIES.sample(random: Random.new(Time.now.to_i))
  end
end

# Execute search with async handling
def execute_search(adapter_key, query_builder)
  Sync do
    Article::SearchFiction.connection(adapter_key)
                          .merge(query_builder)
                          .execute
                          .wait
  end
end

# Benchmark a complexity level
def benchmark_complexity(name, query_module, engines)
  puts "\n#{'=' * 80}"
  puts "#{name} QUERIES"
  puts "=" * 80

  Benchmark.ips do |x|
    x.config(time: BENCHMARK_TIME, warmup: WARMUP_TIME)

    engines.each do |engine_name, adapter_key|
      x.report("#{engine_name.to_s.ljust(15)} #{name}") do
        # Random query each iteration
        query_def = query_module.random
        query_builder = query_def[:query].call(Article::SearchFiction.connection(adapter_key))

        execute_search(adapter_key, query_builder)
      end
    end

    x.compare!
  end
end

# Main execution
begin
  puts "\n🚀 Starting data load..."

  # Load PostgreSQL
  load_postgresql_data

  # Load search engines
  load_search_engine_data("Elasticsearch", :primary)
  load_search_engine_data("OpenSearch", :secondary)

  puts "\n✅ All engines loaded. Starting benchmarks...\n"
  sleep 2 # Let engines settle

  # Run benchmarks
  benchmark_complexity("Simple", SimpleQueries, ENGINES)
  benchmark_complexity("Medium", MediumQueries, ENGINES)
  benchmark_complexity("Complex", ComplexQueries, ENGINES)

  puts "\n#{'=' * 80}"
  puts "BENCHMARK COMPLETE"
  puts "=" * 80
  puts "Dataset: #{RECORD_COUNT} articles"
  puts "Complexity levels: Simple (1 clause), Medium (2-3 clauses), Complex (5+ clauses + aggs)"
  puts "=" * 80
rescue StandardError => e
  puts "\n❌ Error: #{e.message}"
  puts e.backtrace.first(5)
  exit 1
end
