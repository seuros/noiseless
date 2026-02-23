# frozen_string_literal: true

module Noiseless
  class MultiSearch
    def initialize(models: nil, indexes: nil, connection: nil)
      @models = resolve_models(models)
      @indexes = resolve_indexes(indexes)
      @connection = connection || Noiseless.config.default_connection
      @builder = QueryBuilder.new(nil)
    end

    def search(&block)
      yield(@builder) if block

      client = Noiseless.connections.client(@connection)
      ast = @builder.to_ast

      # Override indexes in AST with our multi-model indexes
      ast_with_indexes = AST::Root.new(
        indexes: @indexes,
        bool: ast.bool,
        sort: ast.sort,
        paginate: ast.paginate,
        vector: ast.vector,
        collapse: ast.collapse,
        search_after: ast.search_after,
        aggregations: ast.aggregations,
        hybrid: ast.hybrid,
        pipeline: ast.pipeline,
        image_query: ast.image_query,
        conversation: ast.conversation,
        joins: ast.joins,
        remove_duplicates: ast.remove_duplicates,
        facet_sample_slope: ast.facet_sample_slope,
        pinned_hits: ast.pinned_hits
      )

      raw_response = client.search(ast_with_indexes)
      MultiSearchResponse.new(raw_response, @models, @indexes)
    end

    # Delegate query building methods to the internal builder
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

    def paginate(page, per_page)
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

    private

    def resolve_models(models)
      case models
      when nil
        Noiseless.searchable_models
      when Array
        models.filter_map { |m| resolve_single_model(m) }
      else
        [resolve_single_model(models)].compact
      end
    end

    def resolve_single_model(model)
      case model
      when String, Symbol
        Noiseless.registry.find_model(model)
      when Class
        model
      end
    end

    def resolve_indexes(indexes)
      case indexes
      when nil
        @models.flat_map do |model|
          Array(model.search_index || default_index_name(model))
        end.uniq
      when Array
        indexes.map(&:to_s)
      when String, Symbol
        [indexes.to_s]
      else
        []
      end
    end

    def default_index_name(model_class)
      model_class.name.demodulize.underscore.pluralize
    end
  end

  # Multi-search response class
  class MultiSearchResponse < Response::Base
    def initialize(raw_response, models, indexes)
      super(raw_response)
      @models = models
      @indexes = indexes
      @results_by_model = nil
    end

    def each(&)
      return enum_for(__method__) unless block_given?

      hits.each(&)
    end

    def results_by_model
      @results_by_model ||= group_results_by_model
    end

    def results_for_model(model_class)
      model_key = model_class.name.to_sym
      results_by_model[model_key] || []
    end

    def each_model_result(&)
      return enum_for(__method__) unless block_given?

      results_by_model.each(&)
    end

    def model_counts
      results_by_model.transform_values(&:size)
    end

    def records_by_model
      @records_by_model ||= load_records_by_model
    end

    def records_for_model(model_class)
      model_key = model_class.name.to_sym
      records_by_model[model_key] || []
    end

    private

    def group_results_by_model
      results = {}

      hits.each do |hit|
        model_class = determine_model_class(hit)
        next unless model_class

        model_key = model_class.name.to_sym
        results[model_key] ||= []
        results[model_key] << hit
      end

      results
    end

    def determine_model_class(hit)
      index_name = hit["_index"]

      # First, try to find models registered for this specific index
      models_for_index = Noiseless.registry.models_for_index(index_name)
      return models_for_index.first if models_for_index.size == 1

      # If multiple models or none found, try to infer from index name
      @models.find do |model|
        model_indexes = Array(model.search_index || default_index_name(model))
        model_indexes.include?(index_name)
      end
    end

    def load_records_by_model
      records = {}

      results_by_model.each do |model_key, model_hits|
        model_class = @models.find { |m| m.name.to_sym == model_key }
        next unless model_class.respond_to?(:where)

        ids = model_hits.map { |hit| hit["_id"] }
        loaded_records = model_class.where(id: ids).to_a

        # Sort by search relevance
        sorted_records = model_hits.filter_map do |hit|
          loaded_records.find { |record| record.id.to_s == hit["_id"].to_s }
        end

        records[model_key] = sorted_records
      end

      records
    end

    def default_index_name(model_class)
      model_class.name.demodulize.underscore.pluralize
    end
  end
end
