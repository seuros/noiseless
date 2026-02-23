# frozen_string_literal: true

module Noiseless
  class QueryBuilder
    def initialize(model)
      @model        = model
      @indexes      = determine_indexes(model)
      @nodes        = []
      @aggregations = []
      @collapse     = nil
      @search_after = nil
      @hybrid       = nil
      @pipeline     = nil
      @image_query  = nil
      @conversation = nil
      @joins        = []
      @remove_duplicates = nil
      @facet_sample_slope = nil
      @pinned_hits = nil
    end

    def indexes(names)
      @indexes = Array(names).map(&:to_s)
      self
    end

    def match(field, value)
      @nodes << AST::Match.new(field, value)
      self
    end

    def multi_match(query, fields, **)
      @nodes << AST::MultiMatch.new(query, fields, **)
      self
    end

    def wildcard(field, value)
      @nodes << AST::Wildcard.new(field, value)
      self
    end

    def range(field, gte: nil, lte: nil, gt: nil, lt: nil)
      @nodes << AST::Range.new(field, gte: gte, lte: lte, gt: gt, lt: lt)
      self
    end

    def prefix(field, value)
      @nodes << AST::Prefix.new(field, value)
      self
    end

    def filter(field, value)
      @nodes << AST::Filter.new(field, value)
      self
    end

    alias where filter

    def sort(field, dir = :asc)
      @nodes << AST::Sort.new(field, dir)
      self
    end

    alias order sort

    def paginate(page: 1, per_page: 20)
      @nodes << AST::Paginate.new(page, per_page)
      self
    end

    def limit(size)
      @nodes << AST::Paginate.new(1, size)
      self
    end

    def offset(from)
      # Calculate page based on offset and current per_page
      existing_paginate = @nodes.find { |n| n.is_a?(AST::Paginate) }
      per_page = existing_paginate&.per_page || 20
      page = (from / per_page) + 1
      @nodes.reject! { |n| n.is_a?(AST::Paginate) }
      @nodes << AST::Paginate.new(page, per_page)
      self
    end

    def aggregation(name, type, field: nil, **, &)
      sub_aggs = []
      if block_given?
        sub_builder = AST::AggregationBuilder.new
        sub_builder.instance_eval(&)
        sub_aggs = sub_builder.aggregations
      end

      @aggregations << AST::Aggregation.new(name, type, field: field, sub_aggregations: sub_aggs, **)
      self
    end

    alias agg aggregation

    def collapse(field, inner_hits: nil, max_concurrent_group_searches: nil)
      @collapse = AST::Collapse.new(field, inner_hits: inner_hits,
                                           max_concurrent_group_searches: max_concurrent_group_searches)
      self
    end

    def search_after(values)
      @search_after = AST::SearchAfter.new(values)
      self
    end

    def combined_fields(query, fields, operator: nil, minimum_should_match: nil, **)
      @nodes << AST::CombinedFields.new(query, fields, operator: operator, minimum_should_match: minimum_should_match,
                                                       **)
      self
    end

    def geo_distance(field, lat:, lon:, distance:, **options)
      # Create a special geo filter node
      geo_filter = AST::Filter.new(field, {
                                     geo_distance: {
                                       distance: distance,
                                       "#{field}": { lat: lat, lon: lon }
                                     }.merge(options)
                                   })
      @nodes << geo_filter
      self
    end

    # Vector/semantic search using embeddings (pgvector or OpenSearch knn)
    # @param field [Symbol] The embedding column/field
    # @param embedding [Array<Float>] The query embedding vector
    # @param k [Integer] Number of nearest neighbors (default: 10)
    # @param distance_metric [Symbol] :cosine, :l2, or :inner_product
    def vector(field, embedding, k: 10, distance_metric: :cosine)
      @nodes << AST::Vector.new(field, embedding, k: k, distance_metric: distance_metric)
      self
    end

    alias knn vector
    alias semantic_search vector

    # Hybrid search combining text query with vector search
    # @param text_query [String] The text query for BM25 matching
    # @param embedding [Array<Float>] The query embedding vector
    # @param field [Symbol] The embedding field name
    # @param text_weight [Float] Weight for text search score (default: 0.5)
    # @param vector_weight [Float] Weight for vector search score (default: 0.5)
    # @param k [Integer] Number of nearest neighbors (default: 10)
    def hybrid(text_query, embedding, field:, text_weight: 0.5, vector_weight: 0.5, k: 10)
      vector_node = AST::Vector.new(field, embedding, k: k)
      @hybrid = AST::Hybrid.new(text_query, vector_node, text_weight: text_weight, vector_weight: vector_weight)
      self
    end

    # Apply a search pipeline (OpenSearch only)
    # @param pipeline_name [String] Name of the search pipeline to use
    def pipeline(pipeline_name)
      @pipeline = pipeline_name
      self
    end

    # Image search using visual similarity (Typesense only)
    # @param field [Symbol] The image embedding field name
    # @param image_data [String] Image URL or base64 encoded image
    # @param k [Integer] Number of nearest neighbors (default: 10)
    def image_search(field, image_data, k: 10)
      @image_query = AST::ImageQuery.new(field, image_data, k: k)
      self
    end

    # Conversational/RAG search (Typesense and Elasticsearch)
    # @param model_id [String] The LLM model identifier
    # @param conversation_id [String, nil] ID for multi-turn conversations
    # @param system_prompt [String, nil] Custom system prompt
    def conversational(model_id:, conversation_id: nil, system_prompt: nil)
      @conversation = AST::Conversation.new(
        model_id: model_id,
        conversation_id: conversation_id,
        system_prompt: system_prompt
      )
      self
    end

    alias rag conversational

    # Join with another collection (Typesense only)
    # @param collection [String, Symbol] The collection to join
    # @param on [Hash] Join conditions
    # @param include_fields [Array] Fields to include from joined collection
    # @param strategy [Symbol] Join strategy :left or :inner
    def join(collection, on:, include_fields: [], strategy: :left)
      @joins << AST::Join.new(collection, on: on, include_fields: include_fields, strategy: strategy)
      self
    end

    # Remove duplicate documents in Typesense union search results.
    def remove_duplicates(value: true)
      @remove_duplicates = if value.nil?
                             nil
                           else
                             value ? true : false
                           end
      self
    end

    # Controls dynamic facet sampling behavior in Typesense.
    def facet_sample_slope(value)
      @facet_sample_slope = value
      self
    end

    # Pin specific document IDs to fixed result positions in Typesense.
    #
    # Supported formats:
    # - String: "id1:1,id2:2"
    # - Hash: { "id1" => 1, "id2" => 2 }
    # - Array of pairs: [["id1", 1], ["id2", 2]]
    def pinned_hits(value)
      @pinned_hits = normalize_pinned_hits(value)
      self
    end

    def to_ast
      filter_nodes = @nodes.select { |n| n.is_a?(AST::Filter) }
      vector_nodes = @nodes.select { |n| n.is_a?(AST::Vector) }
      must_nodes = @nodes.reject do |n|
        n.is_a?(AST::Filter) || n.is_a?(AST::Sort) || n.is_a?(AST::Paginate) || n.is_a?(AST::Vector)
      end
      bool_node = AST::Bool.new(must: must_nodes, filter: filter_nodes)
      sort_nodes     = @nodes.select { |n| n.is_a?(AST::Sort) }
      paginate_node  = @nodes.find { |n| n.is_a?(AST::Paginate) }
      AST::Root.new(
        indexes: @indexes,
        bool: bool_node,
        sort: sort_nodes,
        paginate: paginate_node,
        vector: vector_nodes.first, # Only support one vector search per query for now
        collapse: @collapse,
        search_after: @search_after,
        aggregations: @aggregations,
        hybrid: @hybrid,
        pipeline: @pipeline,
        image_query: @image_query,
        conversation: @conversation,
        joins: @joins,
        remove_duplicates: @remove_duplicates,
        facet_sample_slope: @facet_sample_slope,
        pinned_hits: @pinned_hits
      )
    end

    private

    def normalize_pinned_hits(value)
      case value
      when nil
        nil
      when String
        value
      when Hash
        value.map { |id, position| "#{id}:#{position}" }.join(",")
      when Array
        value.map do |entry|
          raise ArgumentError, "pinned_hits array entries must be [id, position]" unless entry.is_a?(Array) && entry.size == 2

          "#{entry[0]}:#{entry[1]}"
        end.join(",")
      else
        raise ArgumentError, "pinned_hits must be a String, Hash, or Array of [id, position]"
      end
    end

    def determine_indexes(model)
      # Check for search_index (plural array) first
      return Array(model.search_index) if model.respond_to?(:search_index) && model.search_index&.any?

      # Check for index_name (singular string) next
      return [model.index_name] if model.respond_to?(:index_name) && model.index_name

      # Fallback to pluralized model name
      [model.name.demodulize.underscore.pluralize]
    end
  end
end
