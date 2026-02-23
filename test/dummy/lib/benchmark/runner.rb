# frozen_string_literal: true

require "benchmark/ips"

module Benchmark
  class Runner
    def self.run_complexity(name, query_module, engines)
      require "benchmark/ips"

      # Pre-build all query variants OUTSIDE benchmark
      queries = query_module::QUERIES.map do |query_def|
        model = Article::SearchFiction.new
        { name: query_def[:name], builder: query_def[:query].call(model) }
      end

      # Wrap entire benchmark in single Sync block - inner Syncs reuse this reactor
      Sync do
        # Warmup connections (optional but helps consistency)
        engines.each_value do |adapter_key|
          queries.first[:builder].execute(connection: adapter_key).wait
        rescue StandardError
          nil
        end

        ::Benchmark.ips do |x|
          x.config(time: Config.benchmark_time, warmup: Config.warmup_time)

          engines.each do |engine_name, adapter_key|
            # Use counter for deterministic rotation instead of broken random
            counter = 0

            x.report("#{engine_name.to_s.ljust(15)} #{name}") do
              query = queries[counter % queries.size]
              counter += 1
              execute_search(adapter_key, query[:builder])
            end
          end

          x.compare!
        end
      end
    end

    def self.execute_search(adapter_key, query_builder)
      # No Sync needed here - we're already inside one from run_complexity
      query_builder.execute(connection: adapter_key).wait
    end
  end
end
