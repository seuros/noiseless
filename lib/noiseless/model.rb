# frozen_string_literal: true

module Noiseless
  class Model
    extend DSL::ClassMethods

    def initialize
      @builder = QueryBuilder.new(self.class)
    end

    def self.search(indexes: nil, connection: nil, response_type: nil)
      client = Noiseless.connections.client(connection || self.connection)
      builder = QueryBuilder.new(self)
      builder.indexes(indexes) if indexes
      yield(builder)
      ast = builder.to_ast
      client.search(ast, model_class: self, response_type: response_type)
    end

    def self.search_sync(indexes: nil, connection: nil, response_type: nil, &)
      Sync do
        search(indexes: indexes, connection: connection, response_type: response_type, &).wait
      end
    end

    # Instance methods that delegate to the query builder
    def match(field, value, **)
      @builder.match(field, value, **)
      self
    end

    def multi_match(query, fields, **)
      @builder.multi_match(query, fields, **)
      self
    end

    def filter(field, value, **)
      @builder.filter(field, value, **)
      self
    end

    def range(field, gte: nil, lte: nil, gt: nil, lt: nil)
      @builder.range(field, gte: gte, lte: lte, gt: gt, lt: lt)
      self
    end

    def sort(field, direction = :asc, **)
      @builder.sort(field, direction, **)
      self
    end

    def limit(size)
      @builder.limit(size)
      self
    end

    def offset(from)
      @builder.offset(from)
      self
    end

    def paginate(page: nil, per_page: nil)
      @builder.paginate(page: page, per_page: per_page)
      self
    end

    def aggregation(name, type, **)
      @builder.aggregation(name, type, **)
      self
    end

    def geo_distance(field, lat:, lon:, distance:, **)
      @builder.geo_distance(field, lat: lat, lon: lon, distance: distance, **)
      self
    end

    def indexes(names)
      @builder.indexes(names)
      self
    end

    def remove_duplicates(value: true)
      @builder.remove_duplicates(value: value)
      self
    end

    def facet_sample_slope(value)
      @builder.facet_sample_slope(value)
      self
    end

    def pinned_hits(value)
      @builder.pinned_hits(value)
      self
    end

    def execute(connection: nil, response_type: nil)
      client = Noiseless.connections.client(connection || self.class.connection)
      ast = @builder.to_ast
      client.search(ast, model_class: self.class, response_type: response_type)
    end

    def execute_sync(connection: nil, response_type: nil)
      Sync do
        execute(connection: connection, response_type: response_type).wait
      end
    end

    delegate :to_ast, to: :@builder
  end
end
