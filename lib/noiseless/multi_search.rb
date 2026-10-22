# frozen_string_literal: true

module Noiseless
  class MultiSearch
    extend QueryDelegation

    delegate_query_methods :match, :multi_match, :filter, :sort, :limit, :offset, :aggregation,
                           :geo_distance, :remove_duplicates, :facet_sample_slope, :pinned_hits,
                           to: :@builder

    def initialize(models: nil, indexes: nil, connection: nil)
      @models = resolve_models(models)
      @indexes = resolve_indexes(indexes)
      @connection = connection || Noiseless.config.default_connection
      @builder = QueryBuilder.new(nil).indexes(@indexes)
    end

    def search(&block)
      yield(@builder) if block

      client = Noiseless.connections.client(@connection)
      ast = @builder.indexes(@indexes).to_ast
      response = Sync { client.search(ast, response_type: :results).wait }
      MultiSearchResponse.new(response.response, @models, @indexes).tap do |result|
        result.include_pagination_info(Pagination.query_options(ast.paginate))
      end
    end

    def paginate(page, per_page)
      @builder.paginate(page: page, per_page: per_page)
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
        @models.flat_map { |model| QueryBuilder.indexes_for(model) }.uniq
      when Array
        indexes.map(&:to_s)
      when String, Symbol
        [indexes.to_s]
      else
        []
      end
    end
  end

  # Multi-search response class
  class MultiSearchResponse < Response::Base
    def initialize(raw_response, models, indexes)
      super(raw_response)
      @models = models
      @indexes = indexes
      @results_by_model = nil
      @models_by_index = {}
      models.each do |model|
        QueryBuilder.indexes_for(model).each { |index| @models_by_index[index] ||= model }
      end
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
      # Only group into requested models, using the same index rules as search.
      @models_by_index[hit["_index"]]
    end

    def load_records_by_model
      records = {}

      results_by_model.each do |model_key, model_hits|
        model_class = @models.find { |m| m.name.to_sym == model_key }
        record_class = RecordClassResolver.resolve(model_class)
        next unless record_class.respond_to?(:where)

        raw = { "hits" => { "hits" => model_hits, "total" => model_hits.size } }
        records[model_key] = Response::Records.new(raw, record_class).to_a
      end

      records
    end
  end
end
