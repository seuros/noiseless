# frozen_string_literal: true

module Benchmark
  module Queries
    module Complex
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
  end
end
