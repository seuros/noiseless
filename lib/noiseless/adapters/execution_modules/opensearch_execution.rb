# frozen_string_literal: true

require "json"
require_relative "es_compatible_execution"

module Noiseless
  module Adapters
    module ExecutionModules
      module OpensearchExecution
        include EsCompatibleExecution

        private

        def execute_search(query_hash, indexes: [], **_opts)
          index_path = indexes.any? ? indexes.join(",") : "_all"
          path = "/#{index_path}/_search"
          body = JSON.generate(query_hash)

          response = post_request(path, body)
          parse_json_response!(response, error_class: Noiseless::SearchError, context: "search #{index_path}")
        ensure
          response&.close
        end

        def execute_create_index(index_name, mappings: nil, settings: nil, **opts)
          body = opts.dup
          body[:mappings] = mappings if mappings
          body[:settings] = settings if settings

          response = put_request("/#{index_name}", body.any? ? JSON.generate(body) : nil)
          parse_json_response!(response, context: "create index #{index_name}")
        ensure
          response&.close
        end

        def execute_index_document(index, id, document, **_opts)
          path = "/#{index}/_doc/#{id}"
          body = JSON.generate(document)

          response = put_request(path, body)
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

        # OpenSearch-specific features
        def execute_point_in_time_search(query_hash, pit_id:, **_opts)
          # Point-in-time search for consistent pagination
          enhanced_query = query_hash.merge(pit: { id: pit_id })
          body = JSON.generate(enhanced_query)

          response = post_request("/_search", body)
          parse_json_response!(response, error_class: Noiseless::SearchError, context: "point-in-time search")
        ensure
          response&.close
        end

        def execute_search_template(template_id:, params: {}, **_opts)
          # OpenSearch search templates
          template_query = {
            id: template_id,
            params: params
          }
          body = JSON.generate(template_query)

          response = post_request("/_search/template", body)
          parse_json_response!(response, error_class: Noiseless::SearchError, context: "search template #{template_id}")
        ensure
          response&.close
        end

        # ============================================
        # Search Pipeline API (OpenSearch 3.x)
        # ============================================

        def execute_create_pipeline(name, request_processors:, response_processors:, description: nil)
          body = {
            description: description,
            request_processors: request_processors,
            response_processors: response_processors
          }.compact

          response = put_request("/_search/pipeline/#{name}", JSON.generate(body))
          JSON.parse(response.read)
        rescue StandardError => e
          { acknowledged: false, error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_get_pipeline(name)
          response = get_request("/_search/pipeline/#{name}")
          JSON.parse(response.read)
        rescue StandardError => e
          { error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_list_pipelines
          response = get_request("/_search/pipeline")
          JSON.parse(response.read)
        rescue StandardError => e
          { error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_delete_pipeline(name)
          response = delete_request("/_search/pipeline/#{name}")
          JSON.parse(response.read)
        rescue StandardError => e
          { acknowledged: false, error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_pipeline_exists?(name)
          response = head_request("/_search/pipeline/#{name}")
          response.success?
        rescue StandardError
          false
        ensure
          response&.close
        end

        # ============================================
        # Query Rules API (OpenSearch 3.x)
        # ============================================

        def execute_create_rule(feature_type, rule_id, attributes:, feature_value:)
          body = {
            match_criteria: {
              query: attributes
            },
            feature_value: feature_value
          }

          response = put_request("/_rules/#{feature_type}/#{rule_id}", JSON.generate(body))
          JSON.parse(response.read)
        rescue StandardError => e
          { acknowledged: false, error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_get_rule(feature_type, rule_id)
          response = get_request("/_rules/#{feature_type}/#{rule_id}")
          JSON.parse(response.read)
        rescue StandardError => e
          { error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_list_rules(feature_type, search_after: nil)
          path = "/_rules/#{feature_type}"
          path += "?search_after=#{search_after}" if search_after

          response = get_request(path)
          JSON.parse(response.read)
        rescue StandardError => e
          { rules: [], error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_delete_rule(feature_type, rule_id)
          response = delete_request("/_rules/#{feature_type}/#{rule_id}")
          JSON.parse(response.read)
        rescue StandardError => e
          { acknowledged: false, error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_rule_exists?(feature_type, rule_id)
          response = head_request("/_rules/#{feature_type}/#{rule_id}")
          response.success?
        rescue StandardError
          false
        ensure
          response&.close
        end
      end
    end
  end
end
