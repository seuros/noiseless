# frozen_string_literal: true

require "json"
require_relative "http_transport"

module Noiseless
  module Adapters
    module ExecutionModules
      # Document and index operations shared by the wire-compatible
      # Elasticsearch and OpenSearch HTTP APIs.
      module EsCompatibleExecution
        include HttpTransport

        private

        def execute_bulk(actions, refresh: nil, **_opts)
          body = actions.map do |action|
            if action[:index]
              action_line = { index: { _index: action[:index][:_index], _id: action[:index][:_id] } }
              data_line = encode_document(action[:index][:data])
              "#{JSON.generate(action_line)}\n#{JSON.generate(data_line)}\n"
            else
              "#{JSON.generate(action)}\n"
            end
          end.join

          path = "/_bulk#{query_string(refresh:, filter_path: 'errors,items.*.status,items.*.error')}"
          response = post_request(path, body, content_type: "application/x-ndjson")
          parse_json_response!(response, context: "bulk")
        ensure
          response&.close
        end

        def execute_delete_index(index_name, **_opts)
          response = delete_request("/#{index_name}")
          # Deleting an absent index is idempotent, matching official ES/OS
          # clients' ignore-404 behaviour.
          return { "acknowledged" => true, "result" => "not_found" } if response.status == 404

          parse_json_response!(response, context: "delete index #{index_name}")
        ensure
          response&.close
        end

        def query_string(refresh: nil, **params)
          params[:refresh] = refresh if refresh
          params.empty? ? "" : "?#{params.map { |key, value| "#{key}=#{value}" }.join('&')}"
        end

        def execute_refresh_index(index_name)
          response = post_request("/#{index_name}/_refresh", nil)
          parse_json_response!(response, context: "refresh index #{index_name}")
        ensure
          response&.close
        end

        def execute_index_exists?(index_name)
          response = head_request("/#{index_name}")
          exists_response?(response, context: "index exists #{index_name}")
        ensure
          response&.close
        end

        def execute_update_document(index, id, changes, refresh: nil, **_opts)
          body = JSON.generate(doc: encode_document(changes))

          response = post_request("/#{index}/_update/#{id}#{query_string(refresh:)}", body)
          parse_json_response!(response, context: "update document #{index}/#{id}")
        ensure
          response&.close
        end

        def execute_delete_document(index, id, refresh: nil, **_opts)
          response = delete_request("/#{index}/_doc/#{id}#{query_string(refresh:)}")
          # 404 covers both a missing document and a missing index; either way
          # the delete is idempotent.
          return { "_index" => index, "_id" => id, "result" => "not_found" } if response.status == 404

          parse_json_response!(response, context: "delete document #{index}/#{id}")
        ensure
          response&.close
        end

        def execute_document_exists?(index, id)
          response = head_request("/#{index}/_doc/#{id}")
          exists_response?(response, context: "document exists #{index}/#{id}")
        ensure
          response&.close
        end
      end
    end
  end
end
