# frozen_string_literal: true

require "json"
require_relative "es_compatible_execution"

module Noiseless
  module Adapters
    module ExecutionModules
      module OpensearchExecution
        include EsCompatibleExecution

        private

        def ast_to_hash(ast_node)
          result = super

          if (knn = result.delete(:knn))
            must = result.dig(:query, :bool, :must)
            result[:query] = must ? { bool: { must: [*must, knn], filter: result.dig(:query, :bool, :filter) }.compact } : knn
            result[:_source] = { excludes: [ast_node.vector.field.to_s] }
          end

          if ast_node.hybrid_search?
            hybrid = ast_node.hybrid
            result[:query][:hybrid][:pagination_depth] = [result[:from].to_i + result[:size].to_i, hybrid.vector.k].max
            result[:search_pipeline] ||= rrf_pipeline(hybrid)
            result[:_source] = { excludes: [hybrid.vector.field.to_s] }
          end

          result
        end

        def build_knn_query(vector_node, filters: nil)
          options = { vector: vector_node.embedding, k: vector_node.k }
          options[:filter] = { bool: { filter: filters } } if filters.present?
          { knn: { vector_node.field.to_s => options } }
        end

        def build_hybrid_query(hybrid_node, query)
          raise ArgumentError, "OpenSearch hybrid search takes filters, not must clauses" if query&.dig(:bool, :must).present?

          text = { multi_match: { query: hybrid_node.text_query, fields: hybrid_node.fields.presence }.compact }
          hybrid = { queries: [text, build_knn_query(hybrid_node.vector)] }
          filters = query&.dig(:bool, :filter)
          hybrid[:filter] = { bool: { filter: filters } } if filters.present?
          { hybrid: hybrid }
        end

        def rrf_pipeline(hybrid_node)
          weights = [hybrid_node.text_weight, hybrid_node.vector_weight]
          ranker = { combination: { technique: "rrf", rank_constant: 60, parameters: { weights: weights } } }
          { phase_results_processors: [{ "score-ranker-processor": ranker }] }
        end

        def encode_vector(values) = [values.pack("e*")].pack("m0")

        def execute_search(query_hash, indexes: [], **_opts)
          index_path = indexes.any? ? indexes.join(",") : "_all"
          pipeline = query_hash[:search_pipeline]
          body = pipeline.is_a?(Hash) ? query_hash : query_hash.except(:search_pipeline)
          path = "/#{index_path}/_search#{query_string(search_pipeline: (pipeline unless pipeline.is_a?(Hash)))}"

          response = post_request(path, JSON.generate(body))
          parse_json_response!(response, error_class: Noiseless::SearchError, context: "search #{index_path}")
        ensure
          response&.close
        end

        def execute_create_index(index_name, mappings: nil, settings: nil, **opts)
          settings = (settings || {}).deep_merge(index: { knn: true }) if knn_mapping?(mappings)
          body = opts.dup
          body[:mappings] = mappings if mappings
          body[:settings] = settings if settings

          response = put_request("/#{index_name}", body.any? ? JSON.generate(body) : nil)
          parse_json_response!(response, context: "create index #{index_name}")
        ensure
          response&.close
        end

        def knn_mapping?(mappings)
          properties = (mappings || {}).with_indifferent_access[:properties] || {}
          properties.values.any? { it[:type].to_s == "knn_vector" }
        end

        def execute_index_document(index, id, document, refresh: nil, **_opts)
          path = "/#{index}/_doc/#{id}#{query_string(refresh:)}"

          response = put_request(path, JSON.generate(encode_document(document)))
          parse_json_response!(response, context: "index document #{index}/#{id}")
        ensure
          response&.close
        end

        def execute_cluster_health(**_opts)
          response = get_request("/_cluster/health")
          JSON.parse(response.read)
        rescue StandardError => e
          {
            cluster_name: "unknown",
            status: "red",
            timed_out: false,
            number_of_nodes: 0,
            number_of_data_nodes: 0,
            active_primary_shards: 0,
            active_shards: 0,
            relocating_shards: 0,
            initializing_shards: 0,
            unassigned_shards: 0,
            error: { type: e.class.name, reason: e.message }
          }
        ensure
          response&.close
        end

        def pit_path = "_search/point_in_time"
        def pit_close_body(pit_id) = { pit_id: [pit_id] }

        def execute_search_template(template_id:, params: {}, **_opts)
          body = JSON.generate(id: template_id, params: params)

          response = post_request("/_search/template", body)
          parse_json_response!(response, error_class: Noiseless::SearchError, context: "search template #{template_id}")
        ensure
          response&.close
        end

        def execute_json(verb, path, body = nil, context:)
          response = case verb
                     when :get then get_request(path)
                     when :delete then delete_request(path)
                     else send(:"#{verb}_request", path, body && JSON.generate(body))
                     end
          parse_json_response!(response, context:)
        ensure
          response&.close
        end

        def execute_exists?(path, context:)
          response = get_request(path)
          exists_response?(response, context:)
        ensure
          response&.close
        end

        def execute_create_pipeline(name, request_processors: nil, response_processors: nil, phase_results_processors: nil,
                                    description: nil)
          body = { description:, request_processors:, response_processors:, phase_results_processors: }.compact
          execute_json(:put, "/_search/pipeline/#{name}", body, context: "create pipeline #{name}")
        end

        def execute_get_pipeline(name) = execute_json(:get, "/_search/pipeline/#{name}", context: "get pipeline #{name}")
        def execute_list_pipelines = execute_json(:get, "/_search/pipeline", context: "list pipelines")
        def execute_delete_pipeline(name) = execute_json(:delete, "/_search/pipeline/#{name}", context: "delete pipeline #{name}")
        def execute_pipeline_exists?(name) = execute_exists?("/_search/pipeline/#{name}", context: "pipeline exists #{name}")

        def execute_create_rule(feature_type, description:, value:, **attributes)
          body = { description:, **attributes, feature_type => value }
          execute_json(:put, "/_rules/#{feature_type}", body, context: "create #{feature_type} rule")
        end

        def execute_update_rule(feature_type, id, **changes)
          execute_json(:put, "/_rules/#{feature_type}/#{id}", changes, context: "update #{feature_type} rule #{id}")
        end

        def execute_get_rule(feature_type, id)
          execute_json(:get, "/_rules/#{feature_type}/#{id}", context: "get #{feature_type} rule #{id}").fetch("rules").first
        end

        def execute_list_rules(feature_type, search_after: nil)
          path = "/_rules/#{feature_type}#{query_string(search_after:)}"
          execute_json(:get, path, context: "list #{feature_type} rules").fetch("rules")
        end

        def execute_delete_rule(feature_type, id)
          execute_json(:delete, "/_rules/#{feature_type}/#{id}", context: "delete #{feature_type} rule #{id}")
        end

        def execute_rule_exists?(feature_type, id)
          execute_exists?("/_rules/#{feature_type}/#{id}", context: "#{feature_type} rule exists #{id}")
        end

        def execute_create_workload_group(name, resource_limits:, resiliency_mode: "soft")
          body = { name:, resiliency_mode:, resource_limits: }
          execute_json(:put, "/_wlm/workload_group", body, context: "create workload group #{name}")
        end

        def execute_get_workload_group(name)
          execute_json(:get, "/_wlm/workload_group/#{name}", context: "get workload group #{name}").fetch("workload_groups").first
        end

        def execute_delete_workload_group(name)
          execute_json(:delete, "/_wlm/workload_group/#{name}", context: "delete workload group #{name}")
        end
      end
    end
  end
end
