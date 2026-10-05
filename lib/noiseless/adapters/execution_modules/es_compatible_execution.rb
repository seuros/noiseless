# frozen_string_literal: true

require "json"

module Noiseless
  module Adapters
    module ExecutionModules
      # Document and index operations shared by the wire-compatible
      # Elasticsearch and OpenSearch HTTP APIs.
      module EsCompatibleExecution
        include HttpTransport

        # Pages through every hit of a query with a point in time and
        # search_after, which unlike from/size has no depth limit and sees a
        # consistent snapshot. The point in time is always closed.
        def each_page(ast_node, keep_alive: "1m", model_class: nil, response_type: nil)
          return enum_for(__method__, ast_node, keep_alive:, model_class:, response_type:) unless block_given?

          Sync do
            query = ast_to_hash(ast_node).except(:from)
            query[:sort] = [*query[:sort], { _shard_doc: "asc" }]
            pit_id = execute_open_pit(ast_node.indexes, keep_alive:)

            loop do
              raw = execute_pit_search(query.merge(pit: { id: pit_id, keep_alive: }))
              hits = raw.dig("hits", "hits")
              break if hits.empty?

              yield ResponseFactory.create(raw, model_class:, response_type:)
              pit_id = raw["pit_id"] || pit_id
              query[:search_after] = hits.last["sort"]
            end
          ensure
            execute_close_pit(pit_id) if pit_id
          end
        end

        private

        def execute_open_pit(indexes, keep_alive:)
          response = post_request("/#{indexes.join(',')}/#{pit_path}?keep_alive=#{keep_alive}", nil)
          parse_json_response!(response, context: "open point in time").then { it["pit_id"] || it["id"] }
        ensure
          response&.close
        end

        def execute_close_pit(pit_id)
          response = delete_request("/#{pit_path}", dump_json(pit_close_body(pit_id)))
          parse_json_response!(response, context: "close point in time")
        ensure
          response&.close
        end

        def execute_pit_search(query_hash)
          response = post_request("/_search", dump_json(query_hash))
          parse_json_response!(response, error_class: Noiseless::SearchError, context: "point-in-time search")
        ensure
          response&.close
        end

        def execute_bulk(actions, refresh: nil, **_opts)
          body = actions.map do |action|
            if action[:index]
              action_line = { index: { _index: action[:index][:_index], _id: action[:index][:_id] } }
              data_line = encode_document(action[:index][:data])
              "#{dump_json(action_line)}\n#{dump_json(data_line)}\n"
            else
              "#{dump_json(action)}\n"
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
          params = params.compact
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
          body = dump_json(doc: encode_document(changes))

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
