# frozen_string_literal: true

module Noiseless
  class Model
    extend DSL::ClassMethods
    extend QueryDelegation

    delegate_query_methods :match, :multi_match, :filter, :range, :sort, :limit, :offset, :paginate,
                           :aggregation, :geo_distance, :indexes, :remove_duplicates, :facet_sample_slope, :pinned_hits,
                           to: :@builder

    # Explicit mapping: index names may be aliases, not record class names.
    # String names are resolved on read so Rails can reload the record class.
    def self.record_class(value = nil)
      unless value.nil?
        raise ArgumentError, "record_class must be a Class or a class name String" unless value.is_a?(Class) || value.is_a?(String)

        return @record_class = value
      end

      configured = @record_class
      configured ||= superclass.record_class unless self == Model
      configured.is_a?(String) ? configured.constantize : configured
    end

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
