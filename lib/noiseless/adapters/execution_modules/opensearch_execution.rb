# frozen_string_literal: true

require "json"

module Noiseless
  module Adapters
    module ExecutionModules
      module OpensearchExecution
        def close
          @clients&.each_value(&:close)
        end

        private

        def execute_search(query_hash, indexes: [], **_opts)
          index_path = indexes.any? ? indexes.join(",") : "_all"
          path = "/#{index_path}/_search"
          body = JSON.generate(query_hash)

          response = post_request(path, body)
          JSON.parse(response.read)
        rescue StandardError => e
          # Return empty response on error to maintain compatibility
          {
            took: 0,
            timed_out: false,
            _shards: { total: 0, successful: 0, skipped: 0, failed: 0 },
            hits: {
              total: { value: 0, relation: "eq" },
              max_score: nil,
              hits: []
            },
            error: {
              type: e.class.name,
              reason: e.message
            }
          }
        ensure
          response&.close
        end

        def execute_bulk(actions, **_opts)
          # Build bulk request body
          bulk_body = actions.map do |action|
            if action[:index]
              action_line = { index: { _index: action[:index][:_index], _id: action[:index][:_id] } }
              data_line = action[:index][:data]
              "#{JSON.generate(action_line)}\n#{JSON.generate(data_line)}\n"
            else
              "#{JSON.generate(action)}\n"
            end
          end.join

          response = post_request("/_bulk", bulk_body, content_type: "application/x-ndjson")
          JSON.parse(response.read)
        rescue StandardError => e
          { items: [], errors: true, error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_create_index(index_name, mappings: nil, settings: nil, **opts)
          body = opts.dup
          body[:mappings] = mappings if mappings
          body[:settings] = settings if settings

          response = put_request("/#{index_name}", body.any? ? JSON.generate(body) : nil)
          JSON.parse(response.read)
        rescue StandardError => e
          { acknowledged: false, error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_delete_index(index_name, **_opts)
          response = delete_request("/#{index_name}")
          JSON.parse(response.read)
        rescue StandardError => e
          { acknowledged: false, error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_refresh_index(index_name)
          response = post_request("/#{index_name}/_refresh", nil)
          JSON.parse(response.read)
        rescue StandardError => e
          {
            "_shards" => {
              "total" => 0,
              "successful" => 0,
              "failed" => 0
            },
            "error" => {
              "type" => e.class.name,
              "reason" => e.message
            }
          }
        ensure
          response&.close
        end

        def execute_index_exists?(index_name)
          response = head_request("/#{index_name}")
          response.success?
        rescue StandardError
          false
        ensure
          response&.close
        end

        def execute_index_document(index, id, document, **_opts)
          path = "/#{index}/_doc/#{id}"
          body = JSON.generate(document)

          response = put_request(path, body)
          JSON.parse(response.read)
        rescue StandardError => e
          { _index: index, _id: id, result: "error", error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_update_document(index, id, changes, **_opts)
          body = JSON.generate(doc: changes)

          response = post_request("/#{index}/_update/#{id}", body)
          JSON.parse(response.read)
        rescue StandardError => e
          { _index: index, _id: id, result: "error", error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_delete_document(index, id, **_opts)
          response = delete_request("/#{index}/_doc/#{id}")
          JSON.parse(response.read)
        rescue StandardError => e
          { _index: index, _id: id, result: "error", error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_document_exists?(index, id)
          response = head_request("/#{index}/_doc/#{id}")
          response.success?
        rescue StandardError
          false
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
          JSON.parse(response.read)
        rescue StandardError => e
          {
            pit_id: pit_id,
            error: { type: e.class.name, reason: e.message },
            hits: { total: { value: 0 }, hits: [] }
          }
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
          JSON.parse(response.read)
        rescue StandardError => e
          {
            error: { type: e.class.name, reason: e.message },
            hits: { total: { value: 0 }, hits: [] }
          }
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

        # HTTP helpers using Async::HTTP with connection pooling
        def get_request(path)
          with_client do |client|
            client.get(path, default_headers)
          end
        end

        def post_request(path, body, content_type: "application/json")
          headers = body ? default_headers + [["content-type", content_type]] : default_headers

          with_client do |client|
            client.post(path, headers, body)
          end
        end

        def put_request(path, body, content_type: "application/json")
          headers = body ? default_headers + [["content-type", content_type]] : default_headers

          with_client do |client|
            client.put(path, headers, body)
          end
        end

        def delete_request(path)
          with_client do |client|
            client.delete(path, default_headers)
          end
        end

        def head_request(path)
          with_client do |client|
            client.head(path, default_headers)
          end
        end

        def with_client
          # Select a random host for load balancing
          host = @hosts.sample
          client = @clients[host]

          yield(client)
        end

        def default_headers
          [
            ["accept", "application/json"],
            ["user-agent", "Noiseless/0.0.0 (Ruby/#{RUBY_VERSION})"]
          ]
        end
      end
    end
  end
end
