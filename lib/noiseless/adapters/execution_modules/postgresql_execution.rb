# frozen_string_literal: true


module Noiseless
  module Adapters
    module ExecutionModules
      # PostgreSQL execution module - translates noiseless AST to PostgreSQL queries
      # Uses pg_trgm for fuzzy matching, unaccent for accent-insensitive search,
      # and optionally pgvector for semantic search
      module PostgresqlExecution
        include PgvectorSupport
        include PostgresqlQuery

        private

        def execute_search(query_hash, model_class: nil, **)
          model = resolve_model(query_hash[:indexes], model_class)
          raise Noiseless::SearchError, "no ActiveRecord model for index #{query_hash[:indexes]&.first.inspect}" unless model

          with_search_errors do
            next execute_vector_search(model, query_hash) if query_hash[:vector] || query_hash[:hybrid]

            scope = build_search_scope(model, query_hash)
            total = scope.except(:order, :limit, :offset).count
            records = apply_pagination(scope, query_hash[:paginate]).to_a

            format_as_search_response(records, model, total: total)
          end
        end

        def with_search_errors
          yield
        rescue ActiveRecord::ConnectionNotEstablished => e
          raise Noiseless::ConnectionError, "postgresql unreachable: #{e.message}"
        rescue Noiseless::Error
          raise
        rescue StandardError => e
          raise Noiseless::SearchError, "postgresql search failed: #{e.message}"
        end

        def execute_vector_search(model, query_hash)
          raise Noiseless::SearchError, "vector search requires the pgvector extension" unless pgvector_available?

          scope = apply_filter_clauses(model.all, query_hash[:bool]&.filter || [], model)
          neighbors, k = nearest(scope, query_hash)

          paginate_node = query_hash[:paginate]
          return format_vector_response(neighbors.to_a, model) unless paginate_node

          records = paginate_neighbors(neighbors, paginate_node, k).to_a
          format_vector_response(records, model, total: [scope.count, k].min)
        end

        def nearest(scope, query_hash)
          if (hybrid = query_hash[:hybrid])
            vector = hybrid.vector
            neighbors = hybrid_search(scope, text_query: hybrid.text_query, embedding: vector.embedding, text_fields: hybrid.fields,
                                             vector_column: vector.field, text_weight: hybrid.text_weight,
                                             vector_weight: hybrid.vector_weight, limit: vector.k)
            return [neighbors, vector.k]
          end

          vector = query_hash[:vector]
          [vector_search(scope, vector.embedding, column: vector.field, limit: vector.k, distance_metric: vector.distance_metric),
           vector.k]
        end

        def paginate_neighbors(scope, paginate_node, k)
          page = paginate_node.page || 1
          per_page = paginate_node.per_page || DEFAULT_LIMIT
          offset = (page - 1) * per_page
          limit = (k - offset).clamp(0, per_page)
          return scope.none if limit.zero?

          scope.limit(limit).offset(offset)
        end

        def format_vector_response(records, model, total: records.size)
          hits = records.map do |record|
            score = if record.has_attribute?(:combined_score)
                      record.combined_score
                    else
                      1.0 - (record.respond_to?(:vector_distance) ? record.vector_distance : 0)
                    end
            {
              "_index" => model.table_name,
              "_id" => record.id.to_s,
              "_score" => score,
              "_source" => record.as_json(except: %w[vector_distance combined_score])
            }
          end

          {
            "took" => 0,
            "timed_out" => false,
            "_shards" => { "total" => 1, "successful" => 1, "skipped" => 0, "failed" => 0 },
            "hits" => {
              "total" => { "value" => total, "relation" => "eq" },
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
        end

        # Document writes are no-ops: the table IS the index, so queries always
        # see current data. Writing indexed documents (which may be transformed
        # by mappings) back into source rows would corrupt them, and deleting a
        # record because its index entry was removed inverts ownership.
        def execute_index_document(index, id, _document, **)
          { "_index" => index, "_id" => id, "result" => "noop" }
        end

        def execute_update_document(index, id, _changes, **)
          { "_index" => index, "_id" => id, "result" => "noop" }
        end

        def execute_delete_document(index, id, **)
          { "_index" => index, "_id" => id, "result" => "noop" }
        end

        def execute_document_exists?(index, id)
          model = resolve_model([index])
          model&.exists?(id: id) || false
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

        # Response formatting

        def format_as_search_response(records, model, total: records.size)
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

        # Helper methods

        def resolve_model(indexes, model_class = nil)
          # The standard Model#execute path passes the Noiseless::Model search
          # class here; only an ActiveRecord model can back a PG search, so
          # fall through to index-name resolution for anything else.
          return model_class if active_record_model?(model_class)

          index_name = indexes&.first
          return nil unless index_name

          # Try cached model first (populated via register_model)
          return @model_class_cache[index_name] if @model_class_cache&.key?(index_name)

          candidate = index_name.to_s.classify.safe_constantize
          candidate if active_record_model?(candidate)
        end

        def active_record_model?(klass)
          klass.is_a?(Class) && klass < ActiveRecord::Base
        end

        def process_bulk_action(action)
          if action[:index]
            { "index" => execute_index_document(action[:index][:_index], action[:index][:_id], nil) }
          elsif action[:delete]
            { "delete" => execute_delete_document(action[:delete][:_index], action[:delete][:_id]) }
          else
            { "error" => "Unknown action type" }
          end
        end
      end
    end
  end
end
