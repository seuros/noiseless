# frozen_string_literal: true

module Noiseless
  module Pagination
    DEFAULT_PER_PAGE = 20
    MAX_PER_PAGE = 100

    # Simple paginated array wrapper - no external dependencies
    class PaginatedArray < Array
      attr_accessor :current_page, :per_page, :total_count

      def initialize(records, current_page:, per_page:, total_count:)
        super(records)
        @current_page = current_page
        @per_page = per_page
        @total_count = total_count
      end

      def total_pages
        return 1 if total_count.zero? || per_page.zero?

        (total_count.to_f / per_page).ceil
      end

      def next_page
        current_page < total_pages ? current_page + 1 : nil
      end

      def prev_page
        current_page > 1 ? current_page - 1 : nil
      end

      def first_page?
        current_page == 1
      end

      def last_page?
        current_page >= total_pages
      end

      def out_of_range?
        current_page > total_pages
      end

      def offset_value
        (current_page - 1) * per_page
      end

      def limit_value
        per_page
      end

      # JSON serialization for API responses
      def pagination_metadata
        {
          current_page: current_page,
          per_page: per_page,
          total_count: total_count,
          total_pages: total_pages,
          next_page: next_page,
          prev_page: prev_page
        }
      end
    end

    # Keyset pagination cursor
    class Cursor
      attr_reader :field, :value, :direction

      def initialize(field:, value:, direction: :asc)
        @field = field.to_s
        @value = value
        @direction = direction.to_sym
      end

      # Encode cursor for API response
      def encode
        Base64.urlsafe_encode64(JSON.generate({ f: field, v: value, d: direction }))
      end

      # Decode cursor from API request
      def self.decode(encoded)
        return nil if encoded.blank?

        data = JSON.parse(Base64.urlsafe_decode64(encoded))
        new(field: data["f"], value: data["v"], direction: data["d"]&.to_sym || :asc)
      rescue StandardError
        nil
      end

      # Build next cursor from last record
      def self.from_record(record, field:, direction: :asc)
        value = record.respond_to?(field) ? record.send(field) : record[field.to_s]
        new(field: field, value: value, direction: direction)
      end
    end

    # Keyset paginated result
    class KeysetResult
      attr_reader :records, :next_cursor, :has_more

      def initialize(records, next_cursor: nil, has_more: false)
        @records = records
        @next_cursor = next_cursor
        @has_more = has_more
      end

      def each(&)
        records.each(&)
      end

      include Enumerable

      def to_a
        records
      end

      delegate :size, to: :records

      delegate :empty?, to: :records

      # JSON serialization for API responses
      def pagination_metadata
        {
          has_more: has_more,
          next_cursor: next_cursor&.encode
        }
      end
    end

    # Search paginator - builds and executes paginated queries
    class SearchPaginator
      include Enumerable

      def initialize(model_class, page: 1, per_page: nil)
        @model_class = model_class
        @current_page = [page.to_i, 1].max
        @per_page = [(per_page || DEFAULT_PER_PAGE).to_i, MAX_PER_PAGE].min
        @query_builder = QueryBuilder.new(model_class)
        @executed = false
        @results = nil
      end

      def page(num)
        SearchPaginator.new(@model_class, page: num, per_page: @per_page)
      end

      def per(num)
        SearchPaginator.new(@model_class, page: @current_page, per_page: num)
      end

      # Pagination info
      attr_reader :current_page

      def limit_value
        @per_page
      end

      def total_count
        execute_search unless @executed
        @total_count || 0
      end

      def total_pages
        return 1 if total_count.zero?

        (total_count.to_f / @per_page).ceil
      end

      def next_page
        current_page < total_pages ? current_page + 1 : nil
      end

      def prev_page
        current_page > 1 ? current_page - 1 : nil
      end

      def first_page?
        current_page == 1
      end

      def last_page?
        current_page >= total_pages
      end

      def out_of_range?
        current_page > total_pages
      end

      def offset_value
        (@current_page - 1) * @per_page
      end

      delegate :size, to: :to_a

      def length
        size
      end

      def empty?
        size.zero?
      end

      # Enumerable interface
      def each(&)
        return enum_for(__method__) unless block_given?

        to_a.each(&)
      end

      def to_a
        execute_search unless @executed
        @results.to_a
      end

      # Query building delegation
      def match(field, value, **)
        @query_builder.match(field, value, **)
        self
      end

      def multi_match(query, fields, **)
        @query_builder.multi_match(query, fields, **)
        self
      end

      def filter(field, value, **)
        @query_builder.filter(field, value, **)
        self
      end

      def sort(field, direction = :asc, **)
        @query_builder.sort(field, direction, **)
        self
      end

      def aggregation(name, type, **)
        @query_builder.aggregation(name, type, **)
        self
      end

      def geo_distance(field, lat:, lon:, distance:, **)
        @query_builder.geo_distance(field, lat: lat, lon: lon, distance: distance, **)
        self
      end

      def vector(field, embedding, **)
        @query_builder.vector(field, embedding, **)
        self
      end

      # Response access
      def results
        execute_search unless @executed
        @results
      end

      def aggregations
        execute_search unless @executed
        @results&.aggregations
      end

      def suggestions
        execute_search unless @executed
        @results&.suggestions
      end

      def hits
        execute_search unless @executed
        @results&.hits || []
      end

      def took
        execute_search unless @executed
        @results&.took
      end

      # Records-specific methods
      def each_with_hit(&)
        return enum_for(__method__) unless block_given?

        execute_search unless @executed
        if @results.respond_to?(:each_with_hit)
          @results.each_with_hit(&)
        else
          to_a.each_with_index { |record, index| yield(record, hits[index]) }
        end
      end

      def map_with_hit(&)
        return enum_for(__method__) unless block_given?

        each_with_hit.map(&)
      end

      # JSON metadata for API responses
      def pagination_metadata
        {
          current_page: current_page,
          per_page: @per_page,
          total_count: total_count,
          total_pages: total_pages,
          next_page: next_page,
          prev_page: prev_page
        }
      end

      private

      def execute_search
        @query_builder.paginate(page: @current_page, per_page: @per_page)

        client = Noiseless.connections.client(@model_class.connection)
        ast = @query_builder.to_ast
        @results = client.search(ast, model_class: @model_class)
        @total_count = @results.total
        @executed = true
      end
    end

    # Extend response classes with pagination support
    module ResponsePagination
      def total_pages
        return 1 if total.zero? || @per_page.nil?

        (total.to_f / @per_page).ceil
      end

      def current_page
        return 1 unless @from && @per_page

        (@from / @per_page) + 1
      end

      def next_page
        current_page < total_pages ? current_page + 1 : nil
      end

      def prev_page
        current_page > 1 ? current_page - 1 : nil
      end

      def first_page?
        current_page == 1
      end

      def last_page?
        current_page >= total_pages
      end

      def out_of_range?
        current_page > total_pages
      end

      def limit_value
        @per_page
      end

      def offset_value
        @from || 0
      end

      def pagination_metadata
        {
          current_page: current_page,
          per_page: @per_page,
          total_count: total,
          total_pages: total_pages,
          next_page: next_page,
          prev_page: prev_page
        }
      end
    end
  end
end
