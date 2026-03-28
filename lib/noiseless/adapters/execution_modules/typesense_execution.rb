# frozen_string_literal: true

require "json"

module Noiseless
  module Adapters
    module ExecutionModules
      module TypesenseExecution
        def close
          @clients&.each_value(&:close)
        end

        private

        # Override AST to Hash conversion for Typesense query format
        def ast_to_hash(ast_node)
          result = {}

          # Build search query from match nodes
          query_parts = build_search_query(ast_node.bool)
          result[:q] = query_parts unless query_parts.empty?

          # Build query_by from multi_match nodes
          query_by_fields = build_query_by_fields(ast_node.bool)
          result[:query_by] = query_by_fields unless query_by_fields.empty?

          # Build filter expressions from filter nodes
          filter_expr = build_filter_expression(ast_node.bool)
          result[:filter_by] = filter_expr unless filter_expr.empty?

          # Build sort expressions from sort nodes
          sort_expr = build_sort_expression(ast_node.sort)
          result[:sort_by] = sort_expr unless sort_expr.empty?

          # Add pagination
          pagination = build_pagination_params(ast_node.paginate)
          result.merge!(pagination)

          # Field collapsing -> Typesense group_by
          if ast_node.collapse
            result[:group_by] = ast_node.collapse.field
            result[:group_limit] = 1 # Collapse shows 1 per group by default
            if ast_node.collapse.max_concurrent_group_searches
              # Typesense v30+: improve found accuracy for grouped results up to this threshold.
              result[:group_max_candidates] = ast_node.collapse.max_concurrent_group_searches
            end
          end

          # Aggregations -> Typesense facet_by
          if ast_node.aggregations.any?
            facet_fields = ast_node.aggregations
                                   .select { |agg| agg.type == :terms }
                                   .filter_map(&:field)

            result[:facet_by] = facet_fields.join(",") if facet_fields.any?
          end

          # Vector search -> Typesense vector_query
          if ast_node.vector_search?
            vector = ast_node.vector
            # Typesense uses format: "field_name:([vector], k:N)"
            vector_str = vector.embedding.join(",")
            result[:vector_query] = "#{vector.field}:([#{vector_str}], k:#{vector.k})"
          end

          # Hybrid search -> Typesense native hybrid with q + vector_query
          if ast_node.hybrid_search?
            hybrid = ast_node.hybrid
            vector = hybrid.vector
            vector_str = vector.embedding.join(",")

            # Typesense natively supports hybrid by combining q and vector_query
            result[:q] = hybrid.text_query
            result[:vector_query] = "#{vector.field}:([#{vector_str}], k:#{vector.k}, alpha:#{hybrid.vector_weight})"
          end

          # Image search -> Typesense image embedding search
          if ast_node.image_search?
            img = ast_node.image_query
            # Typesense accepts image URL or base64 directly in vector_query
            result[:vector_query] = "#{img.field}:(#{img.image_data}, k:#{img.k})"
          end

          # Conversational/RAG search
          if ast_node.conversational?
            conv = ast_node.conversation
            result[:conversation] = true
            result[:conversation_model_id] = conv.model_id
            result[:conversation_id] = conv.conversation_id if conv.conversation_id
            result[:system_prompt] = conv.system_prompt if conv.system_prompt
          end

          # JOINs across collections
          if ast_node.has_joins?
            include_fields = ast_node.joins.map do |join_node|
              fields = join_node.include_fields.join(", ")
              "$#{join_node.collection}(#{fields})"
            end
            result[:include_fields] = include_fields.join(", ")
          end

          # Union-search related options (Typesense v30+).
          result[:remove_duplicates] = ast_node.remove_duplicates unless ast_node.remove_duplicates.nil?
          result[:facet_sample_slope] = ast_node.facet_sample_slope unless ast_node.facet_sample_slope.nil?
          result[:pinned_hits] = ast_node.pinned_hits unless ast_node.pinned_hits.nil?

          result
        end

        def build_search_query(bool_node)
          # Combine all match queries into a single search string
          queries = bool_node.must.filter_map do |node|
            case node
            when AST::Match
              "#{node.field}:#{node.value}"
            when AST::MultiMatch
              # For Typesense, multi_match becomes a broader search across fields
              node.query
            when AST::Range
              # Range queries are handled in filters, not search
              nil
            else
              node.respond_to?(:value) ? "#{node.field}:#{node.value}" : nil
            end
          end
          queries.join(" ")
        end

        def build_query_by_fields(bool_node)
          # Extract fields from multi_match nodes for Typesense query_by parameter
          fields = bool_node.must.filter_map do |node|
            case node
            when AST::MultiMatch
              node.fields
            end
          end.flatten.uniq

          fields.join(",")
        end

        def build_filter_expression(bool_node)
          # Convert filter and range nodes to Typesense filter expressions
          filters = bool_node.filter.map { |filter| "#{filter.field}:=#{filter.value}" }

          # Add range filters from must clause
          range_filters = bool_node.must.filter_map do |node|
            next unless node.is_a?(AST::Range)

            conditions = []
            conditions << "#{node.field}:>#{node.gt}" if node.gt
            conditions << "#{node.field}:>=#{node.gte}" if node.gte
            conditions << "#{node.field}:<#{node.lt}" if node.lt
            conditions << "#{node.field}:<=#{node.lte}" if node.lte
            conditions.join(" && ")
          end

          (filters + range_filters).compact.join(" && ")
        end

        def build_sort_expression(sort_nodes)
          # Convert sort nodes to Typesense sort format
          sorts = sort_nodes.map do |sort|
            direction = sort.direction == :desc ? "desc" : "asc"
            "#{sort.field}:#{direction}"
          end
          sorts.join(",")
        end

        def build_pagination_params(paginate_node)
          return { page: 1, per_page: 20 } unless paginate_node

          {
            page: paginate_node.page,
            per_page: paginate_node.per_page
          }
        end

        def execute_search(query_hash, collections: [], **_opts)
          collection_path = collections.any? ? "/collections/#{collections.first}/documents/search" : "/multi_search"

          # Convert query_hash to URL params for Typesense
          params = query_hash.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")
          path = "#{collection_path}?#{params}"

          response = get_request(path)
          result = JSON.parse(response.read)

          # Convert Typesense format to Elasticsearch-like format
          {
            took: result["search_time_ms"] || 0,
            timed_out: false,
            _shards: { total: 1, successful: 1, skipped: 0, failed: 0 },
            hits: {
              total: { value: result["found"] || 0, relation: "eq" },
              max_score: nil,
              hits: (result["hits"] || []).map do |hit|
                {
                  _index: collections.first || "typesense",
                  _type: "_doc",
                  _id: hit["document"]["id"],
                  _score: hit["text_match"] || 1.0,
                  _source: hit["document"]
                }
              end
            }
          }
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
          # Typesense uses different endpoints for different operations
          results = actions.map do |action|
            if action[:index]
              collection = action[:index][:_index]
              id = action[:index][:_id]
              document = action[:index][:data]

              path = "/collections/#{collection}/documents"
              body = JSON.generate(document.merge(id: id))

              response = post_request(path, body)
              result = JSON.parse(response.read)
              response.close

              { index: { _id: result["id"], status: 201, result: "created" } }
            elsif action[:delete]
              collection = action[:delete][:_index]
              id = action[:delete][:_id]

              path = "/collections/#{collection}/documents/#{id}"

              response = delete_request(path)
              response.close

              { delete: { _id: id, status: 200, result: "deleted" } }
            else
              { error: { status: 400, error: "Unsupported action" } }
            end
          end

          { items: results }
        rescue StandardError => e
          { items: [], errors: true, error: { type: e.class.name, reason: e.message } }
        end

        def execute_create_index(collection_name, mappings: nil, **_opts)
          # Typesense calls indexes "collections"
          schema = {
            name: collection_name,
            fields: []
          }

          # Convert mappings to Typesense schema if provided
          if mappings && mappings["properties"]
            schema[:fields] = mappings["properties"].map do |field_name, field_config|
              {
                name: field_name,
                type: map_type_to_typesense(field_config["type"] || "string"),
                facet: field_config["facet"] || false
              }
            end
          end

          body = JSON.generate(schema)
          response = post_request("/collections", body)
          result = JSON.parse(response.read)

          { acknowledged: true, index: result["name"] }
        rescue StandardError => e
          { acknowledged: false, error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_delete_index(collection_name, **_opts)
          response = delete_request("/collections/#{collection_name}")
          JSON.parse(response.read)

          { acknowledged: true }
        rescue StandardError => e
          { acknowledged: false, error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_index_exists?(collection_name)
          response = head_request("/collections/#{collection_name}")
          response.success?
        rescue StandardError
          false
        ensure
          response&.close
        end

        def execute_index_document(collection, id, document, **_opts)
          path = "/collections/#{collection}/documents"
          body = JSON.generate(document.merge(id: id))

          response = post_request(path, body)
          result = JSON.parse(response.read)

          { _index: collection, _id: result["id"], result: "created" }
        rescue StandardError => e
          { _index: collection, _id: id, result: "error", error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_update_document(collection, id, changes, **_opts)
          # Typesense doesn't have partial updates, so we need to fetch and merge
          get_response = get_request("/collections/#{collection}/documents/#{id}")
          document = JSON.parse(get_response.read)
          get_response.close

          updated_document = document.merge(changes).merge(id: id)
          body = JSON.generate(updated_document)

          response = put_request("/collections/#{collection}/documents/#{id}", body)
          result = JSON.parse(response.read)

          { _index: collection, _id: result["id"], result: "updated" }
        rescue StandardError => e
          { _index: collection, _id: id, result: "error", error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close if defined?(response)
        end

        def execute_delete_document(collection, id, **_opts)
          response = delete_request("/collections/#{collection}/documents/#{id}")

          { _index: collection, _id: id, result: "deleted" }
        rescue StandardError => e
          { _index: collection, _id: id, result: "error", error: { type: e.class.name, reason: e.message } }
        ensure
          response&.close
        end

        def execute_document_exists?(collection, id)
          response = head_request("/collections/#{collection}/documents/#{id}")
          response.success?
        rescue StandardError
          false
        ensure
          response&.close
        end

        def execute_cluster_health(**_opts)
          response = get_request("/health")
          health_data = JSON.parse(response.read)

          # Convert Typesense health format to match expected format
          {
            cluster_name: "typesense",
            status: health_data["ok"] ? "green" : "red",
            timed_out: false,
            number_of_nodes: 1,
            number_of_data_nodes: 1,
            active_primary_shards: 0,
            active_shards: 0,
            typesense_ok: health_data["ok"]
          }
        rescue StandardError => e
          {
            cluster_name: "unknown",
            status: "red",
            timed_out: false,
            number_of_nodes: 0,
            number_of_data_nodes: 0,
            active_primary_shards: 0,
            active_shards: 0,
            error: { type: e.class.name, reason: e.message }
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
          headers = [
            ["accept", "application/json"],
            ["user-agent", "Noiseless/#{Noiseless::VERSION} (Ruby/#{RUBY_VERSION})"]
          ]

          # Add Typesense API key if configured
          if @connection_params && @connection_params[:api_key]
            headers << ["X-TYPESENSE-API-KEY",
                        @connection_params[:api_key]]
          end

          headers
        end

        # rubocop:disable Lint/DuplicateBranch
        def map_type_to_typesense(elasticsearch_type)
          # Map Elasticsearch types to Typesense types
          case elasticsearch_type
          when "text", "keyword"
            "string"
          when "long", "integer", "short", "byte", "date"
            "int64" # date uses Unix timestamps
          when "double", "float", "half_float", "scaled_float"
            "float"
          when "boolean"
            "bool"
          else
            "string" # Default to string for unknown types
          end
        end
        # rubocop:enable Lint/DuplicateBranch
      end
    end
  end
end
