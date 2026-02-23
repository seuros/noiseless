# frozen_string_literal: true

require_relative "pgvector_support"

module Noiseless
  module Adapters
    module ExecutionModules
      # PostgreSQL execution module - translates noiseless AST to PostgreSQL queries
      # Uses pg_trgm for fuzzy matching, unaccent for accent-insensitive search,
      # and optionally pgvector for semantic search
      module PostgresqlExecution
        include PgvectorSupport

        SIMILARITY_THRESHOLD = 0.3
        DEFAULT_LIMIT = 20

        private

        def execute_search(query_hash, model_class: nil, **)
          model = resolve_model(query_hash[:indexes], model_class)
          return empty_response unless model

          # Check if this is a vector search
          return execute_vector_search(model, query_hash) if query_hash[:vector]

          scope = build_search_scope(model, query_hash)
          records = scope.to_a

          format_as_search_response(records, model)
        rescue StandardError => e
          error_response(e)
        end

        def execute_vector_search(model, query_hash)
          vector_node = query_hash[:vector]
          return empty_response unless vector_node && pgvector_available?

          # Start with base scope
          scope = model.all

          # Apply any filters first
          scope = apply_filter_clauses(scope, query_hash[:bool]&.filter || [])

          # Apply vector search
          scope = vector_search(
            scope,
            vector_node.embedding,
            column: vector_node.field,
            limit: vector_node.k,
            distance_metric: vector_node.distance_metric
          )

          records = scope.to_a
          format_vector_response(records, model, vector_node)
        rescue StandardError => e
          error_response(e)
        end

        def format_vector_response(records, model, _vector_node)
          hits = records.map do |record|
            distance = record.respond_to?(:vector_distance) ? record.vector_distance : 0
            {
              "_index" => model.table_name,
              "_id" => record.id.to_s,
              "_score" => 1.0 - distance, # Convert distance to similarity score
              "_source" => record.as_json(except: [:vector_distance])
            }
          end

          {
            "took" => 0,
            "timed_out" => false,
            "_shards" => { "total" => 1, "successful" => 1, "skipped" => 0, "failed" => 0 },
            "hits" => {
              "total" => { "value" => hits.size, "relation" => "eq" },
              "max_score" => hits.first&.dig("_score"),
              "hits" => hits
            }
          }
        end

        def execute_bulk(actions, **)
          results = actions.map do |action|
            process_bulk_action(action)
          end

          { "items" => results, "errors" => results.any? { |r| r["error"] } }
        end

        def execute_create_index(_index_name, **)
          # No-op for PostgreSQL - tables already exist
          { "acknowledged" => true }
        end

        def execute_delete_index(_index_name, **)
          # No-op - we don't delete tables via search adapter
          { "acknowledged" => true }
        end

        def execute_index_exists?(index_name)
          model = resolve_model([index_name])
          model.present? && model.table_exists?
        rescue StandardError
          false
        end

        def execute_index_document(index, id, document, **)
          model = resolve_model([index])
          return { "_id" => id, "result" => "error", "error" => "Model not found" } unless model

          record = model.find_or_initialize_by(id: id)
          record.assign_attributes(document.slice(*model.column_names))
          record.save!

          { "_index" => index, "_id" => id, "result" => record.previously_new_record? ? "created" : "updated" }
        rescue StandardError => e
          { "_index" => index, "_id" => id, "result" => "error", "error" => e.message }
        end

        def execute_update_document(index, id, changes, **)
          model = resolve_model([index])
          return { "_id" => id, "result" => "error", "error" => "Model not found" } unless model

          record = model.find(id)
          record.update!(changes.slice(*model.column_names))

          { "_index" => index, "_id" => id, "result" => "updated" }
        rescue ActiveRecord::RecordNotFound
          { "_index" => index, "_id" => id, "result" => "not_found" }
        rescue StandardError => e
          { "_index" => index, "_id" => id, "result" => "error", "error" => e.message }
        end

        def execute_delete_document(index, id, **)
          model = resolve_model([index])
          return { "_id" => id, "result" => "error", "error" => "Model not found" } unless model

          model.destroy(id)
          { "_index" => index, "_id" => id, "result" => "deleted" }
        rescue ActiveRecord::RecordNotFound
          { "_index" => index, "_id" => id, "result" => "not_found" }
        rescue StandardError => e
          { "_index" => index, "_id" => id, "result" => "error", "error" => e.message }
        end

        def execute_document_exists?(index, id)
          model = resolve_model([index])
          model&.exists?(id: id) || false
        rescue StandardError
          false
        end

        def execute_cluster_health(**)
          # Verify PostgreSQL connection
          ActiveRecord::Base.connection.execute("SELECT 1")
          {
            "cluster_name" => "postgresql",
            "status" => "green",
            "number_of_nodes" => 1
          }
        rescue StandardError => e
          {
            "cluster_name" => "postgresql",
            "status" => "red",
            "error" => e.message
          }
        end

        # Query building methods

        def build_search_scope(model, query_hash)
          scope = model.all

          # Apply must clauses (full-text search)
          scope = apply_must_clauses(scope, query_hash[:bool]&.must || [], model)

          # Apply filter clauses (exact matches)
          scope = apply_filter_clauses(scope, query_hash[:bool]&.filter || [])

          # Apply sorting
          scope = apply_sorting(scope, query_hash[:sort] || [])

          # Apply pagination
          apply_pagination(scope, query_hash[:paginate])
        end

        def apply_must_clauses(scope, must_nodes, model)
          return scope if must_nodes.empty?

          must_nodes.each do |node|
            scope = case node
                    when AST::Match
                      apply_match(scope, node, model)
                    when AST::MultiMatch
                      apply_multi_match(scope, node, model)
                    when AST::Wildcard
                      apply_wildcard(scope, node)
                    when AST::Range
                      apply_range(scope, node)
                    when AST::Prefix
                      apply_prefix(scope, node)
                    else
                      scope
                    end
          end

          scope
        end

        def apply_match(scope, node, model)
          field = node.field.to_s
          value = node.value.to_s

          # Use pg_trgm similarity for fuzzy matching with unaccent
          if trgm_available? && text_column?(model, field)
            scope.where(
              "unaccent(#{quoted_column(field)}) % unaccent(?) OR " \
              "unaccent(#{quoted_column(field)}) ILIKE unaccent(?)",
              value,
              "%#{sanitize_like(value)}%"
            )
          else
            # Fallback to ILIKE
            scope.where("#{quoted_column(field)} ILIKE ?", "%#{sanitize_like(value)}%")
          end
        end

        def apply_multi_match(scope, node, model)
          query = node.query.to_s
          fields = node.fields.map(&:to_s)

          conditions = fields.map do |field|
            if trgm_available? && text_column?(model, field)
              "(unaccent(#{quoted_column(field)}) % unaccent(?) OR " \
                "unaccent(#{quoted_column(field)}) ILIKE unaccent(?))"
            else
              "#{quoted_column(field)} ILIKE ?"
            end
          end

          params = fields.flat_map do |field|
            if trgm_available? && text_column?(model, field)
              [query, "%#{sanitize_like(query)}%"]
            else
              ["%#{sanitize_like(query)}%"]
            end
          end

          scope.where(conditions.join(" OR "), *params)
        end

        def apply_wildcard(scope, node)
          field = node.field.to_s
          # Convert OpenSearch wildcards to SQL: * -> %, ? -> _
          pattern = node.value.to_s.tr("*", "%").tr("?", "_")

          scope.where("#{quoted_column(field)} ILIKE ?", pattern)
        end

        def apply_range(scope, node)
          field = quoted_column(node.field.to_s)

          scope = scope.where("#{field} >= ?", node.gte) if node.gte
          scope = scope.where("#{field} <= ?", node.lte) if node.lte
          scope = scope.where("#{field} > ?", node.gt) if node.gt
          scope = scope.where("#{field} < ?", node.lt) if node.lt

          scope
        end

        def apply_prefix(scope, node)
          scope.where("#{quoted_column(node.field.to_s)} ILIKE ?", "#{sanitize_like(node.value)}%")
        end

        def apply_filter_clauses(scope, filter_nodes)
          return scope if filter_nodes.empty?

          filter_nodes.each do |node|
            value = node.value

            scope = if value.is_a?(Hash) && value[:geo_distance]
                      apply_geo_filter(scope, node)
                    else
                      scope.where(node.field => value)
                    end
          end

          scope
        end

        def apply_geo_filter(scope, node)
          # Requires PostGIS
          geo_config = node.value[:geo_distance]
          distance = geo_config[:distance]
          field = node.field.to_s

          # Find the geo point in config
          geo_point = geo_config.find { |_k, v| v.is_a?(Hash) && v[:lat] && v[:lon] }&.last
          return scope unless geo_point

          # Use PostGIS ST_DWithin for efficient geo filtering
          scope.where(
            "ST_DWithin(#{field}::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)",
            geo_point[:lon],
            geo_point[:lat],
            parse_distance(distance)
          )
        rescue StandardError
          # If PostGIS not available, skip geo filter
          scope
        end

        def apply_sorting(scope, sort_nodes)
          return scope if sort_nodes.empty?

          order_clauses = sort_nodes.map do |node|
            direction = node.direction.to_s.upcase == "DESC" ? "DESC" : "ASC"
            "#{quoted_column(node.field.to_s)} #{direction}"
          end

          scope.order(Arel.sql(order_clauses.join(", ")))
        end

        def apply_pagination(scope, paginate_node)
          page = paginate_node&.page || 1
          per_page = paginate_node&.per_page || DEFAULT_LIMIT

          offset = (page - 1) * per_page

          scope.limit(per_page).offset(offset)
        end

        # Response formatting

        def format_as_search_response(records, model)
          total = records.size

          hits = records.map do |record|
            {
              "_index" => model.table_name,
              "_id" => record.id.to_s,
              "_score" => 1.0,
              "_source" => record.as_json
            }
          end

          {
            "took" => 0,
            "timed_out" => false,
            "_shards" => { "total" => 1, "successful" => 1, "skipped" => 0, "failed" => 0 },
            "hits" => {
              "total" => { "value" => total, "relation" => "eq" },
              "max_score" => hits.any? ? 1.0 : nil,
              "hits" => hits
            }
          }
        end

        def empty_response
          {
            "took" => 0,
            "timed_out" => false,
            "_shards" => { "total" => 1, "successful" => 1, "skipped" => 0, "failed" => 0 },
            "hits" => {
              "total" => { "value" => 0, "relation" => "eq" },
              "max_score" => nil,
              "hits" => []
            }
          }
        end

        def error_response(error)
          {
            "took" => 0,
            "timed_out" => false,
            "_shards" => { "total" => 1, "successful" => 0, "skipped" => 0, "failed" => 1 },
            "hits" => {
              "total" => { "value" => 0, "relation" => "eq" },
              "max_score" => nil,
              "hits" => []
            },
            "error" => { "type" => error.class.name, "reason" => error.message }
          }
        end

        # Helper methods

        def resolve_model(indexes, model_class = nil)
          return model_class if model_class

          index_name = indexes&.first
          return nil unless index_name

          # Try cached model first
          return @model_class_cache[index_name] if @model_class_cache&.key?(index_name)

          # Try to infer model from index name
          model_name = index_name.to_s.classify
          model_name.constantize
        rescue NameError
          nil
        end

        def trgm_available?
          @trgm_available ||= available_extensions.include?("pg_trgm")
        end

        def unaccent_available?
          @unaccent_available ||= available_extensions.include?("unaccent")
        end

        def text_column?(model, field)
          column = model.columns_hash[field.to_s]
          column && %i[string text].include?(column.type)
        end

        def quoted_column(field)
          ActiveRecord::Base.connection.quote_column_name(field)
        end

        def sanitize_like(value)
          # Escape special LIKE characters
          value.to_s.gsub(/[%_\\]/) { |x| "\\#{x}" }
        end

        def parse_distance(distance)
          # Parse OpenSearch distance format (e.g., "10km", "5mi")
          case distance.to_s
          when /(\d+(?:\.\d+)?)\s*km/i
            ::Regexp.last_match(1).to_f * 1000
          when /(\d+(?:\.\d+)?)\s*mi/i
            ::Regexp.last_match(1).to_f * 1609.34
          when /(\d+(?:\.\d+)?)\s*m/i
            ::Regexp.last_match(1).to_f
          else
            distance.to_f
          end
        end

        def process_bulk_action(action)
          if action[:index]
            index = action[:index][:_index]
            id = action[:index][:_id]
            data = action[:index][:data]

            result = execute_index_document(index, id, data)
            { "index" => result }
          elsif action[:delete]
            index = action[:delete][:_index]
            id = action[:delete][:_id]

            result = execute_delete_document(index, id)
            { "delete" => result }
          else
            { "error" => "Unknown action type" }
          end
        end
      end
    end
  end
end
