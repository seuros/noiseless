# frozen_string_literal: true

require "json"
require_relative "es_compatible_execution"

module Noiseless
  module Adapters
    module ExecutionModules
      module ElasticsearchExecution
        include EsCompatibleExecution

        private

        def execute_search(query_hash, indexes: [], **_opts)
          path = indexes.any? ? "/#{indexes.join(',')}/_search" : "/_search"
          body = dump_json(query_hash)

          response = post_request(path, body)
          parse_json_response!(response, error_class: Noiseless::SearchError, context: "search")
        ensure
          response&.close
        end

        def execute_create_index(index_name, mappings: nil, settings: nil, **_opts)
          body = {}
          body[:mappings] = mappings if mappings
          body[:settings] = settings if settings

          response = put_request("/#{index_name}", body.any? ? dump_json(body) : nil)
          parse_json_response!(response, context: "create index #{index_name}")
        ensure
          response&.close
        end

        def execute_index_document(index, id, document, refresh: nil, **_opts)
          path = (id ? "/#{index}/_doc/#{id}" : "/#{index}/_doc") + query_string(refresh:)
          body = dump_json(encode_document(document))

          response = id ? put_request(path, body) : post_request(path, body)
          parse_json_response!(response, context: "index document #{index}/#{id}")
        ensure
          response&.close
        end

        def pit_path = "_pit"
        def pit_close_body(pit_id) = { id: pit_id }

        def execute_cluster_health(**_opts)
          response = get_request("/_cluster/health")
          JSON.parse(response.read)
        rescue StandardError => e
          {
            "cluster_name" => "unknown",
            "status" => "red",
            "timed_out" => false,
            "number_of_nodes" => 0,
            "number_of_data_nodes" => 0,
            "active_primary_shards" => 0,
            "active_shards" => 0,
            "error" => {
              "type" => e.class.name,
              "reason" => e.message
            }
          }
        ensure
          response&.close
        end
      end
    end
  end
end
