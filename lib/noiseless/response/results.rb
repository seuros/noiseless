# frozen_string_literal: true

module Noiseless
  module Response
    class Results < Base
      def each
        return enum_for(__method__) unless block_given?

        hits.each do |hit|
          yield Result.new(hit)
        end
      end

      def sources
        @sources ||= hits.map { |hit| hit["_source"] }
      end

      alias records sources

      def each_source(&)
        return enum_for(__method__) unless block_given?

        sources.each(&)
      end

      def map_source(&)
        return enum_for(__method__) unless block_given?

        sources.map(&)
      end

      def first
        hit = hits.first
        hit ? Result.new(hit) : nil
      end

      def last
        hit = hits.last
        hit ? Result.new(hit) : nil
      end

      def [](index)
        hit = hits[index]
        hit ? Result.new(hit) : nil
      end

      def to_a
        hits.map { |hit| Result.new(hit) }
      end

      def map
        return enum_for(__method__) unless block_given?

        results = []
        each do |result|
          results << yield(result)
        end
        results
      end

      def select
        return enum_for(__method__) unless block_given?

        results = []
        each do |result|
          results << result if yield(result)
        end
        results
      end

      def ids
        @ids ||= hits.map { |hit| hit["_id"] }
      end

      def scores
        @scores ||= hits.map { |hit| hit["_score"] }
      end

      # Make results enumerable with source property
      def find
        return enum_for(__method__) unless block_given?

        hits.each do |hit|
          result = Result.new(hit)
          return result if yield(result)
        end
        nil
      end

      class Result
        attr_reader :source

        def initialize(hit)
          @hit = hit
          @source = hit["_source"]
        end

        def id
          @hit["_id"]
        end

        def score
          @hit["_score"]
        end

        delegate :[], to: :@source
      end
    end
  end
end
