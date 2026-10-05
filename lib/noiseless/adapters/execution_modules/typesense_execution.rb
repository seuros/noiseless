# frozen_string_literal: true

require "cgi/escape"
require "json"
require_relative "http_transport"

module Noiseless
  module Adapters
    module ExecutionModules
      module TypesenseExecution
        include HttpTransport

        # Typesense stores date fields as int64, so times travel as epoch seconds.
        TYPESENSE_JSON = JSON::Coder.new do |object|
          if object.respond_to?(:to_time) then object.to_time.to_i
          elsif object.is_a?(BigDecimal) then object.to_f
          else object.respond_to?(:as_json) ? object.as_json : object.to_s
          end
        end

        private

        def ast_to_hash(ast_node)
          result = {}

          query_parts = build_search_query(ast_node.bool)
          result[:q] = query_parts.empty? ? "*" : query_parts

          query_by_fields = build_query_by_fields(ast_node.bool)
          result[:query_by] = query_by_fields unless query_by_fields.empty?

          filter_expr = build_filter_expression(ast_node.bool)
          result[:filter_by] = filter_expr unless filter_expr.empty?

          sort_expr = build_sort_expression(ast_node.sort)
          result[:sort_by] = sort_expr unless sort_expr.empty?

          result.merge!(build_pagination_params(ast_node.paginate))
          result[:enable_highlight_v1] = false

          if ast_node.collapse
            result[:group_by] = ast_node.collapse.field
            result[:group_limit] = 1
          end

          terms_aggregations = ast_node.aggregations.select { it.type == :terms && it.field }
          if terms_aggregations.any?
            result[:facet_by] = terms_aggregations.map(&:field).uniq.join(",")
            result[:aggregation_names] = terms_aggregations.to_h { [it.field, it.name] }
          end

          if ast_node.vector_search?
            vector = ast_node.vector
            result[:vector_query] = "#{vector.field}:([#{vector.embedding.join(',')}], k:#{vector.k})"
            result[:exclude_fields] = vector.field.to_s
          end

          if ast_node.hybrid_search?
            hybrid = ast_node.hybrid
            vector = hybrid.vector
            raise ArgumentError, "Typesense hybrid search needs fields: to run the text query against" if hybrid.fields.empty?

            result[:q] = hybrid.text_query
            result[:query_by] = hybrid.fields.join(",")
            result[:vector_query] =
              "#{vector.field}:([#{vector.embedding.join(',')}], k:#{vector.k}, alpha:#{hybrid.vector_weight})"
            result[:exclude_fields] = vector.field.to_s
          end

          if ast_node.image_search?
            img = ast_node.image_query
            result[:vector_query] = "#{img.field}:([], image:#{img.image_data}, k:#{img.k})"
            result[:exclude_fields] = img.field.to_s
          end

          if ast_node.conversational?
            conv = ast_node.conversation
            result[:conversation] = true
            result[:conversation_model_id] = conv.model_id
            result[:conversation_id] = conv.conversation_id if conv.conversation_id
          end

          if ast_node.has_joins?
            result[:include_fields] = ast_node.joins.map { "$#{it.collection}(#{it.include_fields.presence&.join(', ') || '*'})" }.join(", ")
            inner = ast_node.joins.select(&:inner_join?).map { "$#{it.collection}(id:*)" }
            result[:filter_by] = [result[:filter_by], *inner].compact.join(" && ") if inner.any?
          end

          result[:remove_duplicates] = ast_node.remove_duplicates unless ast_node.remove_duplicates.nil?
          result[:facet_sample_slope] = ast_node.facet_sample_slope unless ast_node.facet_sample_slope.nil?
          result[:pinned_hits] = ast_node.pinned_hits unless ast_node.pinned_hits.nil?

          result
        end

        def build_search_query(bool_node)
          bool_node.must.filter_map do |node|
            case node
            when AST::Match then node.value.to_s
            when AST::MultiMatch then node.query.to_s
            end
          end.join(" ")
        end

        def build_query_by_fields(bool_node)
          bool_node.must.flat_map do |node|
            case node
            when AST::Match then [node.field.to_s]
            when AST::MultiMatch then node.fields.map(&:to_s)
            else []
            end
          end.uniq.join(",")
        end

        def build_filter_expression(bool_node)
          filters = bool_node.filter.map { |filter| "#{filter.field}:=#{filter_value(filter.value)}" }

          range_filters = bool_node.must.filter_map do |node|
            next unless node.is_a?(AST::Range)

            conditions = []
            conditions << "#{node.field}:>#{filter_value(node.gt)}" if node.gt
            conditions << "#{node.field}:>=#{filter_value(node.gte)}" if node.gte
            conditions << "#{node.field}:<#{filter_value(node.lt)}" if node.lt
            conditions << "#{node.field}:<=#{filter_value(node.lte)}" if node.lte
            conditions.join(" && ")
          end

          (filters + range_filters).compact.join(" && ")
        end

        def dump_json(object) = TYPESENSE_JSON.dump(object)

        def filter_value(value)
          return value.to_time.to_i.to_s if value.respond_to?(:to_time) && !value.is_a?(String)

          case value
          when Array then "[#{value.map { filter_value(it) }.join(',')}]"
          when Numeric, true, false then value.to_s
          else
            string = value.to_s
            raise ArgumentError, "Typesense filter values cannot contain backticks: #{string.inspect}" if string.include?("`")

            "`#{string}`"
          end
        end

        def build_sort_expression(sort_nodes)
          sort_nodes.map { |sort| "#{sort.field}:#{sort.direction == :desc ? 'desc' : 'asc'}" }.join(",")
        end

        def build_pagination_params(paginate_node)
          { page: paginate_node&.page || 1, per_page: paginate_node&.per_page || 20 }
        end

        def execute_search(query_hash, indexes: [], **_opts)
          collections = Array(indexes).map(&:to_s)
          raise Noiseless::SearchError, "Typesense search needs a collection" if collections.empty?

          aggregation_names = query_hash[:aggregation_names] || {}
          params = query_hash.except(:aggregation_names, :remove_duplicates)
          context = "search #{collections.join(',')}"

          result = if collections.one?
                     body = { searches: [params.merge(collection: collections.first)] }
                     single = post_json!("/multi_search", body, context:).fetch("results").first
                     raise_search_error!(single, context) if single["error"]
                     single
                   else
                     body = { union: true, searches: collections.map { params.except(:page, :per_page).merge(collection: it) } }
                     body[:remove_duplicates] = query_hash[:remove_duplicates] unless query_hash[:remove_duplicates].nil?
                     post_json!("/multi_search?page=#{params[:page]}&per_page=#{params[:per_page]}", body, context:)
                   end

          search_response(result, collections.first, aggregation_names)
        end

        def post_json!(path, body, context:)
          response = post_request(path, dump_json(body))
          parse_json_response!(response, error_class: Noiseless::SearchError, context:)
        ensure
          response&.close
        end

        def raise_search_error!(result, context)
          raise Noiseless::SearchError.new("#{context}: #{result['error']}", status: result["code"])
        end

        def search_response(result, default_collection, aggregation_names)
          hits = if result["grouped_hits"]
                   result["grouped_hits"].filter_map { it["hits"].first }
                 else
                   result["hits"] || []
                 end

          {
            "took" => result["search_time_ms"] || 0,
            "timed_out" => false,
            "hits" => {
              "total" => { "value" => result["found"] || 0, "relation" => "eq" },
              "max_score" => nil,
              "hits" => hits.map { search_hit(it, default_collection) }
            },
            "aggregations" => facet_aggregations(result["facet_counts"], aggregation_names)
          }
        end

        def search_hit(hit, default_collection)
          score = hit.dig("hybrid_search_info", "rank_fusion_score") ||
                  (hit["vector_distance"] && (1.0 - hit["vector_distance"])) ||
                  hit["text_match"] || 1.0

          {
            "_index" => hit["collection"] || default_collection,
            "_id" => hit.dig("document", "id"),
            "_score" => score,
            "_source" => hit["document"]
          }
        end

        def facet_aggregations(facet_counts, aggregation_names)
          Array(facet_counts).each_with_object({}) do |facet, aggregations|
            name = aggregation_names.fetch(facet["field_name"], facet["field_name"])
            buckets = facet["counts"].map { { "key" => it["value"], "doc_count" => it["count"] } }
            aggregations[name] = { "buckets" => buckets }
          end
        end

        def execute_bulk(actions, **_opts)
          items = Array.new(actions.size)
          indexed = actions.each_with_index.group_by { |action, _| action.dig(:index, :_index) || action.dig(:delete, :_index) }

          indexed.each do |collection, pairs|
            imports, deletes = pairs.partition { |action, _| action[:index] }
            import_documents(collection, imports, items) if imports.any?
            delete_documents(collection, deletes, items) if deletes.any?
          end

          { "items" => items, "errors" => items.any? { it.values.first["error"] } }
        end

        def import_documents(collection, pairs, items)
          jsonl = pairs.map { |action, _| dump_json(typesense_document(collection, action[:index][:data], action[:index][:_id])) }.join("\n")
          response = post_request("/collections/#{collection}/documents/import?action=upsert", jsonl, content_type: "text/plain")
          body = response.read
          unless response.success?
            raise Noiseless::RequestError.new("import #{collection}: #{error_message(body, response.status)}", status: response.status)
          end

          body.each_line.zip(pairs).each do |line, (action, position)|
            result = JSON.parse(line)
            items[position] = {
              "index" => {
                "_index" => collection,
                "_id" => action[:index][:_id].to_s,
                "status" => result["success"] ? 201 : result["code"],
                "error" => (result["error"] unless result["success"])
              }.compact
            }
          end
        ensure
          response&.close
        end

        def delete_documents(collection, pairs, items)
          ids = pairs.map { |action, _| action[:delete][:_id] }
          filter = CGI.escape("id:#{filter_value(ids.map(&:to_s))}")
          response = delete_request("/collections/#{collection}/documents?filter_by=#{filter}")
          parse_json_response!(response, context: "delete documents #{collection}")

          pairs.each do |action, position|
            items[position] = { "delete" => { "_index" => collection, "_id" => action[:delete][:_id].to_s, "status" => 200 } }
          end
        ensure
          response&.close
        end

        def typesense_document(collection, document, id)
          shape_document(collection, document).merge("id" => id.to_s)
        end

        def shape_document(collection, document)
          arrays = array_fields(collection)
          document.to_h.to_h do |key, value|
            key = key.to_s
            [key, arrays.include?(key) && !value.nil? && !value.is_a?(Array) ? [value] : value]
          end
        end

        def array_fields(collection)
          (@array_fields ||= {})[collection.to_s] ||= begin
            response = get_request("/collections/#{collection}")
            fields = response.success? ? JSON.parse(response.read).fetch("fields") : []
            fields.filter_map { it["name"] if it["type"].end_with?("[]") }.to_set
          ensure
            response&.close
          end
        end

        def error_message(body, status)
          parsed = JSON.parse(body)
          parsed.is_a?(Hash) && parsed["message"] ? parsed["message"] : "HTTP #{status}"
        rescue JSON::ParserError
          "HTTP #{status}"
        end

        def execute_create_index(collection_name, mappings: nil, **_opts)
          @array_fields&.delete(collection_name.to_s)
          properties = (mappings || {}).with_indifferent_access[:properties] || {}
          fields = properties.map { |name, config| typesense_field(name, config) }
          fields = [{ name: ".*", type: "auto" }] if fields.empty?

          response = post_request("/collections", dump_json(name: collection_name, fields:))
          result = parse_json_response!(response, context: "create collection #{collection_name}")

          { "acknowledged" => true, "index" => result["name"] }
        ensure
          response&.close
        end

        def typesense_field(name, config)
          type = map_type_to_typesense(config[:type].to_s)
          field = { name: name.to_s, type: type, optional: true }
          field[:num_dim] = config[:dims] || config[:dimension] if type == "float[]"
          field[:facet] = true if config[:facet] || config[:type].to_s == "keyword"
          field[:reference] = config[:reference] if config[:reference]
          field
        end

        def execute_delete_index(collection_name, **_opts)
          @array_fields&.delete(collection_name.to_s)
          response = delete_request("/collections/#{collection_name}")
          return { "acknowledged" => true, "result" => "not_found" } if response.status == 404

          parse_json_response!(response, context: "delete collection #{collection_name}")
          { "acknowledged" => true }
        ensure
          response&.close
        end

        def execute_index_exists?(collection_name)
          response = get_request("/collections/#{collection_name}")
          exists_response?(response, context: "collection exists #{collection_name}")
        ensure
          response&.close
        end

        def execute_index_document(collection, id, document, **_opts)
          response = post_request("/collections/#{collection}/documents?action=upsert",
                                  dump_json(typesense_document(collection, document, id)))
          result = parse_json_response!(response, context: "index document #{collection}/#{id}")

          { "_index" => collection, "_id" => result["id"], "result" => "upserted" }
        ensure
          response&.close
        end

        def execute_update_document(collection, id, changes, **_opts)
          response = patch_request("/collections/#{collection}/documents/#{id}", dump_json(shape_document(collection, changes)))
          result = parse_json_response!(response, context: "update document #{collection}/#{id}")

          { "_index" => collection, "_id" => result["id"], "result" => "updated" }
        ensure
          response&.close
        end

        def execute_delete_document(collection, id, **_opts)
          response = delete_request("/collections/#{collection}/documents/#{id}?ignore_not_found=true")
          parse_json_response!(response, context: "delete document #{collection}/#{id}")

          { "_index" => collection, "_id" => id.to_s, "result" => "deleted" }
        ensure
          response&.close
        end

        def execute_document_exists?(collection, id)
          response = get_request("/collections/#{collection}/documents/#{id}?include_fields=id")
          exists_response?(response, context: "document exists #{collection}/#{id}")
        ensure
          response&.close
        end

        def execute_cluster_health(**_opts)
          response = get_request("/health")
          health_data = JSON.parse(response.read)

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

        def default_headers
          headers = super
          headers << ["X-TYPESENSE-API-KEY", @connection_params[:api_key]] if @connection_params&.dig(:api_key)
          headers
        end

        def map_type_to_typesense(elasticsearch_type)
          case elasticsearch_type
          when "long", "integer", "short", "byte", "date" then "int64"
          when "double", "float", "half_float", "scaled_float" then "float"
          when "boolean" then "bool"
          when "dense_vector", "knn_vector" then "float[]"
          when "keyword" then "string[]"
          else "string"
          end
        end
      end
    end
  end
end
