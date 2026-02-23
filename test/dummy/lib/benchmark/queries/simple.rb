# frozen_string_literal: true

module Benchmark
  module Queries
    module Simple
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
  end
end
