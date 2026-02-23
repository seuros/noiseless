# frozen_string_literal: true

require_relative "../benchmark/config"
require_relative "../benchmark/loader"
require_relative "../benchmark/runner"
require_relative "../benchmark/queries/simple"
require_relative "../benchmark/queries/medium"
require_relative "../benchmark/queries/complex"

namespace :benchmark do
  desc "Clean all benchmark data from all 4 engines"
  task clean: :environment do
    require "async"

    Rails.logger.tagged("BENCHMARK", "CLEAN") { Rails.logger.info "Cleaning benchmark data from all engines..." }

    # Clean PostgreSQL
    Article.delete_all
    Rails.logger.info "PostgreSQL cleaned"

    # Clean search engines
    Benchmark::Config.enabled_engines.each do |engine|
      next if engine == :postgresql

      adapter_key = Benchmark::Config::ENGINES[engine]
      Sync do
        client = Noiseless.connections.client(adapter_key)
        begin
          client.delete_index("articles").wait
          Rails.logger.info "#{engine.to_s.capitalize} index deleted"
        rescue StandardError => e
          Rails.logger.warn "#{engine.to_s.capitalize}: #{e.message}"
        end
      end
    end

    Rails.logger.info "All engines cleaned"
  end

  desc "Seed all 4 engines with 10k benchmark articles"
  task seed: :environment do
    require "async"

    Rails.logger.tagged("BENCHMARK", "SEED") { Rails.logger.info "Seeding all engines with benchmark data..." }

    # Seed PostgreSQL
    Benchmark::Loader.load_postgresql

    # Seed search engines
    enabled = Benchmark::Config.enabled_engines.reject { |e| e == :postgresql }
    enabled.each do |engine|
      adapter_key = Benchmark::Config::ENGINES[engine]
      Benchmark::Loader.load_search_engine(engine.to_s.capitalize, adapter_key)
    end

    Rails.logger.info "All engines seeded. Waiting #{Benchmark::Config.settle_time}s for engines to settle..."
    sleep Benchmark::Config.settle_time
    Rails.logger.info "Ready for benchmarking"
  end

  desc "Run simple query benchmarks (auto-seeds if needed)"
  task simple: :environment do
    Rake::Task["benchmark:_ensure_data"].invoke

    puts "\n#{'=' * 80}"
    puts "SIMPLE QUERIES"
    puts "=" * 80

    engines = Benchmark::Config.enabled_engines.to_h { |e| [e, Benchmark::Config::ENGINES[e]] }
    Benchmark::Runner.run_complexity("Simple", Benchmark::Queries::Simple, engines)
  end

  desc "Run medium query benchmarks (auto-seeds if needed)"
  task medium: :environment do
    Rake::Task["benchmark:_ensure_data"].invoke

    puts "\n#{'=' * 80}"
    puts "MEDIUM QUERIES"
    puts "=" * 80

    engines = Benchmark::Config.enabled_engines.to_h { |e| [e, Benchmark::Config::ENGINES[e]] }
    Benchmark::Runner.run_complexity("Medium", Benchmark::Queries::Medium, engines)
  end

  desc "Run complex query benchmarks (auto-seeds if needed)"
  task complex: :environment do
    Rake::Task["benchmark:_ensure_data"].invoke

    puts "\n#{'=' * 80}"
    puts "COMPLEX QUERIES"
    puts "=" * 80

    engines = Benchmark::Config.enabled_engines.to_h { |e| [e, Benchmark::Config::ENGINES[e]] }
    Benchmark::Runner.run_complexity("Complex", Benchmark::Queries::Complex, engines)
  end

  desc "Run complete benchmark suite (clean → seed → all complexity levels)"
  task full: :environment do
    Rake::Task["benchmark:clean"].invoke
    Rake::Task["benchmark:seed"].invoke
    Rake::Task["benchmark:simple"].invoke
    Rake::Task["benchmark:medium"].invoke
    Rake::Task["benchmark:complex"].invoke

    puts "\n#{'=' * 80}"
    puts "BENCHMARK COMPLETE"
    puts "=" * 80
    puts "Dataset: #{Article.count} articles"
    puts "Complexity levels: Simple (1 clause), Medium (2-3 clauses), Complex (5+ clauses + aggs)"
    puts "=" * 80
  end

  # Private task to ensure data exists before running benchmarks
  task _ensure_data: :environment do
    unless Benchmark::Loader.data_exists?
      Rails.logger.warn "No benchmark data found. Seeding automatically..."
      Rake::Task["benchmark:seed"].invoke
    end
  end
end
