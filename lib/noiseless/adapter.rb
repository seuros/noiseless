# frozen_string_literal: true

require "async"
require_relative "introspection"

module Noiseless
  class Adapter
    include Instrumentation
    include Introspection

    def initialize(hosts: [], **connection_params)
      @hosts = hosts
      @connection_params = connection_params.dup
      @connection_params.delete(:async)
    end

    def async_context?
      true
    end

    # Convert AST to Hash/JSON before execution
    def search(ast_node, model_class: nil, response_type: nil, **)
      query_hash = ast_to_hash(ast_node)

      Async do
        raw_response = instrument(:search, indexes: ast_node.indexes, query: query_hash) do
          execute_search(query_hash, indexes: ast_node.indexes, **)
        end

        ResponseFactory.create(
          raw_response,
          model_class: model_class,
          response_type: response_type,
          query_hash: query_hash
        )
      end
    end

    def bulk(actions, **)
      Async do
        instrument(:bulk, actions_count: actions.size) do
          execute_bulk(actions, **)
        end
      end
    end

    def create_index(index_name, **)
      Async do
        instrument(:create_index, index: index_name) do
          execute_create_index(index_name, **)
        end
      end
    end

    def delete_index(index_name, **)
      Async do
        instrument(:delete_index, index: index_name) do
          execute_delete_index(index_name, **)
        end
      end
    end

    def index_exists?(index_name)
      Async do
        execute_index_exists?(index_name)
      end
    end

    def index_document(index:, id:, document:, **)
      Async do
        instrument(:index_document, index: index, id: id) do
          execute_index_document(index, id, document, **)
        end
      end
    end

    def update_document(index:, id:, changes:, **)
      Async do
        instrument(:update_document, index: index, id: id, changes_count: changes.size) do
          execute_update_document(index, id, changes, **)
        end
      end
    end

    def delete_document(index:, id:, **)
      Async do
        instrument(:delete_document, index: index, id: id) do
          execute_delete_document(index, id, **)
        end
      end
    end

    def document_exists?(index:, id:)
      Async do
        execute_document_exists?(index, id)
      end
    end

    # Raw search method for backward compatibility
    def search_raw(query_body, indexes: [], **)
      Async do
        instrument(:search, indexes: indexes, query: query_body) do
          execute_search(query_body, indexes: indexes, **)
        end
      end
    end

    private

    # Convert AST to Hash - override in subclasses for adapter-specific format
    def ast_to_hash(ast_node)
      result = {}

      query_hash = build_query_hash(ast_node.bool)
      result[:query] = query_hash unless query_hash.empty?

      sort_hash = build_sort_hash(ast_node.sort)
      result[:sort] = sort_hash unless sort_hash.empty?

      # Handle search_after (cursor pagination) vs offset pagination
      if ast_node.search_after
        result[:search_after] = ast_node.search_after.values
        result[:size] = ast_node.paginate&.per_page || 20
      else
        pagination = build_pagination_hash(ast_node.paginate)
        result[:from] = pagination[:from]
        result[:size] = pagination[:size]
      end

      # Field collapsing
      result[:collapse] = build_collapse_hash(ast_node.collapse) if ast_node.collapse

      # Aggregations
      result[:aggs] = build_aggregations_hash(ast_node.aggregations) if ast_node.aggregations.any?

      # Vector/kNN search (OpenSearch/Elasticsearch compatible)
      result[:knn] = build_knn_query(ast_node.vector) if ast_node.vector_search?

      # Hybrid search (combines text + vector with RRF or weighted scoring)
      if ast_node.hybrid_search?
        hybrid_config = build_hybrid_query(ast_node.hybrid)
        result.merge!(hybrid_config)
      end

      # Search pipeline (OpenSearch only)
      result[:search_pipeline] = ast_node.pipeline if ast_node.has_pipeline?

      result
    end

    def build_knn_query(vector_node)
      {
        field: vector_node.field.to_s,
        query_vector: vector_node.embedding,
        k: vector_node.k,
        num_candidates: vector_node.k * 10
      }
    end

    # Build hybrid query using RRF (Reciprocal Rank Fusion) for OpenSearch/Elasticsearch
    def build_hybrid_query(hybrid_node)
      {
        query: {
          bool: {
            should: [
              {
                match: {
                  _all: hybrid_node.text_query
                }
              }
            ]
          }
        },
        knn: build_knn_query(hybrid_node.vector),
        rank: {
          rrf: {
            window_size: hybrid_node.vector.k * 2
          }
        }
      }
    end

    def build_query_hash(bool_node)
      return {} if bool_node.must.empty? && bool_node.filter.empty?

      must_queries = bool_node.must.filter_map { |node| build_must_clause(node) }

      {
        bool: {
          must: must_queries,
          filter: bool_node.filter.map { |f| { term: { f.field => f.value } } }
        }.reject { |_, v| v.empty? }
      }
    end

    def build_sort_hash(sort_nodes)
      return [] if sort_nodes.empty?

      sort_nodes.map { |s| { s.field => { order: s.direction } } }
    end

    def build_pagination_hash(paginate_node)
      return { from: 0, size: 20 } unless paginate_node

      {
        from: (paginate_node.page - 1) * paginate_node.per_page,
        size: paginate_node.per_page
      }
    end

    # Override in subclasses
    def execute_search(_query_hash, **_opts)
      {
        took: 1,
        hits: {
          total: { value: 0 },
          hits: []
        }
      }
    end

    def execute_bulk(actions, **_opts)
      {
        items: actions.map { |_action| { index: { status: 201 } } }
      }
    end

    def execute_create_index(_index_name, **_opts)
      { acknowledged: true }
    end

    def execute_delete_index(_index_name, **_opts)
      { acknowledged: true }
    end

    def execute_index_exists?(_index_name)
      true
    end

    def execute_index_document(index, id, _document, **_opts)
      { _index: index, _id: id, result: "created" }
    end

    def execute_update_document(index, id, _changes, **_opts)
      { _index: index, _id: id, result: "updated" }
    end

    def execute_delete_document(index, id, **_opts)
      { _index: index, _id: id, result: "deleted" }
    end

    def execute_document_exists?(_index, _id)
      true
    end

    def build_must_clause(node)
      case node
      when AST::Match
        { match: { node.field => node.value } }
      when AST::MultiMatch
        { multi_match: { query: node.query, fields: node.fields }.merge(node.options) }
      when AST::CombinedFields
        { combined_fields: { query: node.query, fields: node.fields }.merge(node.options) }
      when AST::Wildcard
        { wildcard: { node.field => node.value } }
      when AST::Range
        range_options = {
          gte: node.gte,
          lte: node.lte,
          gt: node.gt,
          lt: node.lt
        }.compact
        { range: { node.field => range_options } }
      when AST::Prefix
        { prefix: { node.field => node.value } }
      else
        node.to_hash
      end
    end

    def build_collapse_hash(collapse_node)
      result = { field: collapse_node.field }
      result[:inner_hits] = collapse_node.inner_hits if collapse_node.inner_hits
      if collapse_node.max_concurrent_group_searches
        result[:max_concurrent_group_searches] =
          collapse_node.max_concurrent_group_searches
      end
      result
    end

    def build_aggregations_hash(aggregations)
      aggregations.each_with_object({}) do |agg, hash|
        hash[agg.name] = build_single_aggregation(agg)
      end
    end

    def build_single_aggregation(agg)
      result = {}

      # Build the aggregation type hash
      agg_body = {}
      agg_body[:field] = agg.field if agg.field
      agg_body.merge!(agg.options)

      result[agg.type] = agg_body

      # Add sub-aggregations if any
      result[:aggs] = build_aggregations_hash(agg.sub_aggregations) if agg.sub_aggregations.any?

      result
    end
  end
end
