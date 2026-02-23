# frozen_string_literal: true

module Noiseless
  module Response
    class Records < Base
      def initialize(raw_response, model_class)
        super
        @records = nil
        @record_hit_map = nil
      end

      def each(&)
        return enum_for(__method__) unless block_given?

        records.each(&)
      end

      def each_with_hit
        return enum_for(__method__) unless block_given?

        records.each_with_index do |record, index|
          hit = hits[record_hit_map[record] || index]
          yield(record, hit)
        end
      end

      def map_with_hit(&)
        return enum_for(__method__) unless block_given?

        each_with_hit.map(&)
      end

      def records
        @records ||= load_records_with_pagination
      end

      delegate :first, to: :records

      delegate :last, to: :records

      delegate :[], to: :records

      def to_a
        records
      end

      private

      def load_records_with_pagination
        records = load_records

        # Wrap in PaginatedArray for pagination metadata
        current_page = @from && @per_page ? (@from / @per_page) + 1 : 1
        per_page = @per_page || Pagination::DEFAULT_PER_PAGE

        Pagination::PaginatedArray.new(
          records,
          current_page: current_page,
          per_page: per_page,
          total_count: total
        )
      end

      def load_records
        return [] if hits.empty? || !model_class.respond_to?(:where)

        # Extract IDs from hits
        ids = hits.map { |hit| hit["_id"] }

        # Load records from database
        loaded_records = model_class.where(id: ids).to_a

        # Create mapping from record to hit index for correlation
        @record_hit_map = {}

        # Sort records by the order they appear in search results
        sorted_records = []
        hits.each_with_index do |hit, hit_index|
          record = loaded_records.find { |r| r.id.to_s == hit["_id"].to_s }
          if record
            sorted_records << record
            @record_hit_map[record] = hit_index
          end
        end

        sorted_records
      end

      def record_hit_map
        @record_hit_map ||= {}
      end
    end
  end
end
