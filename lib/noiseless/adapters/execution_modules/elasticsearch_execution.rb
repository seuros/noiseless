# frozen_string_literal: true

require "json"

module Noiseless
  module Adapters
    module ExecutionModules
      module ElasticsearchExecution
        def close
          @clients&.each_value(&:close)
        end

        private

        def execute_search(query_hash, indexes: [], **_opts)
          path = indexes.any? ? "/#{indexes.join(',')}/_search" : "/_search"
          body = JSON.generate(query_hash)

          response = post_request(path, body)
          JSON.parse(response.read)
        ensure
          response&.close
        end

        def execute_bulk(actions, **_opts)
          body = "#{actions.map { |action| JSON.generate(action) }.join("\n")}\n"

          response = post_request("/_bulk", body, content_type: "application/x-ndjson")
          JSON.parse(response.read)
        ensure
          response&.close
        end

        def execute_create_index(index_name, mappings: nil, settings: nil, **_opts)
          body = {}
          body[:mappings] = mappings if mappings
          body[:settings] = settings if settings

          response = put_request("/#{index_name}", body.any? ? JSON.generate(body) : nil)
          JSON.parse(response.read)
        ensure
          response&.close
        end

        def execute_delete_index(index_name, **_opts)
          response = delete_request("/#{index_name}")
          JSON.parse(response.read)
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
          path = id ? "/#{index}/_doc/#{id}" : "/#{index}/_doc"
          body = JSON.generate(document)

          response = id ? put_request(path, body) : post_request(path, body)
          JSON.parse(response.read)
        ensure
          response&.close
        end

        def execute_update_document(index, id, changes, **_opts)
          body = JSON.generate(doc: changes)

          response = post_request("/#{index}/_update/#{id}", body)
          JSON.parse(response.read)
        ensure
          response&.close
        end

        def execute_delete_document(index, id, **_opts)
          response = delete_request("/#{index}/_doc/#{id}")
          JSON.parse(response.read)
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
            ["user-agent", "Noiseless/#{Noiseless::VERSION} (Ruby/#{RUBY_VERSION})"]
          ]
        end
      end
    end
  end
end
