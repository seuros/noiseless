# frozen_string_literal: true

module Benchmark
  class Config
    ENGINES = {
      elasticsearch: :primary,
      opensearch: :opensearch,
      typesense: :typesense,
      postgresql: :postgresql
    }.freeze

    def self.enabled_engines
      if ENV["ENGINES"]
        ENV["ENGINES"].split(",").map(&:strip).map(&:to_sym).select { |e| ENGINES.key?(e) }
      else
        ENGINES.keys
      end
    end

    def self.warmup_time
      ENV.fetch("WARMUP_TIME", 1).to_i
    end

    def self.benchmark_time
      ENV.fetch("BENCHMARK_TIME", 3).to_i
    end

    def self.settle_time
      ENV.fetch("SETTLE_TIME", 2).to_i
    end
  end
end
