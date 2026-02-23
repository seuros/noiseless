# frozen_string_literal: true

module Benchmark
  module Queries
    module Medium
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
  end
end
