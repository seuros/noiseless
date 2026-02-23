# frozen_string_literal: true

module Noiseless
  module Adapters
    module ExecutionModules
      # pgvector support for semantic/vector search in PostgreSQL
      # Provides similarity search using embeddings
      #
      # Required:
      #   CREATE EXTENSION IF NOT EXISTS vector;
      #
      # Table setup:
      #   ALTER TABLE your_table ADD COLUMN embedding vector(1536);
      #   CREATE INDEX ON your_table USING ivfflat (embedding vector_cosine_ops);
      #
      module PgvectorSupport
        # Perform semantic search using vector similarity
        #
        # @param scope [ActiveRecord::Relation] The base scope to search
        # @param embedding [Array<Float>] The query embedding vector
        # @param column [Symbol] The column containing embeddings (default: :embedding)
        # @param limit [Integer] Maximum results to return
        # @param distance_threshold [Float] Maximum distance threshold (optional)
        # @param distance_metric [Symbol] :cosine, :l2, or :inner_product
        # @return [ActiveRecord::Relation] Scope with vector similarity ordering
        #
        def vector_search(scope, embedding, column: :embedding, limit: 20, distance_threshold: nil,
                          distance_metric: :cosine)
          return scope unless pgvector_available?

          vector_string = "[#{embedding.join(',')}]"
          distance_op = distance_operator(distance_metric)

          # Build the query with distance calculation
          scope = scope.select(
            "#{scope.table_name}.*",
            "#{quoted_column(column)} #{distance_op} '#{vector_string}' AS vector_distance"
          )

          # Apply distance threshold if specified
          if distance_threshold
            scope = scope.where(
              "#{quoted_column(column)} #{distance_op} '#{vector_string}' < ?",
              distance_threshold
            )
          end

          # Order by similarity (ascending distance = more similar)
          scope.order(Arel.sql("#{quoted_column(column)} #{distance_op} '#{vector_string}'"))
               .limit(limit)
        end

        # Hybrid search combining text and vector search
        #
        # @param scope [ActiveRecord::Relation] Base scope
        # @param text_query [String] Text query for pg_trgm search
        # @param embedding [Array<Float>] Query embedding for vector search
        # @param text_fields [Array<Symbol>] Fields to search with text
        # @param vector_column [Symbol] Column containing embeddings
        # @param text_weight [Float] Weight for text similarity (0.0-1.0)
        # @param vector_weight [Float] Weight for vector similarity (0.0-1.0)
        # @return [ActiveRecord::Relation]
        #
        def hybrid_search(scope, text_query:, embedding:, text_fields:, vector_column: :embedding,
                          text_weight: 0.5, vector_weight: 0.5, limit: 20)
          return scope unless pgvector_available?

          vector_string = "[#{embedding.join(',')}]"
          text_conditions = text_fields.map { |f| "similarity(#{quoted_column(f)}, ?)" }.join(" + ")
          text_similarity_count = text_fields.size

          # Normalized combined score
          scope.select(
            "#{scope.table_name}.*",
            # Text similarity (0-1 per field, averaged)
            Arel.sql(
              "(#{text_conditions}) / #{text_similarity_count} * #{text_weight} AS text_score"
            ),
            # Vector similarity (convert distance to similarity: 1 - distance for cosine)
            "(1 - (#{quoted_column(vector_column)} <=> '#{vector_string}')) * #{vector_weight} AS vector_score",
            # Combined score
            "(((#{text_conditions}) / #{text_similarity_count}) * #{text_weight} + " \
            "(1 - (#{quoted_column(vector_column)} <=> '#{vector_string}')) * #{vector_weight}) AS combined_score"
          ).where(
            "#{text_conditions} > 0 OR #{quoted_column(vector_column)} IS NOT NULL",
            *Array.new(text_similarity_count, text_query)
          ).order(Arel.sql("combined_score DESC"))
               .limit(limit)
               .tap { |s| s.bind_values.concat(Array.new(text_similarity_count, text_query)) }
        end

        # Execute a KNN (K-Nearest Neighbors) search
        #
        # @param model [Class] The ActiveRecord model
        # @param embedding [Array<Float>] Query embedding
        # @param k [Integer] Number of nearest neighbors
        # @param column [Symbol] Embedding column
        # @param filters [Hash] Additional WHERE conditions
        # @return [Array<Hash>] Results with distance scores
        #
        def knn_search(model, embedding, k: 10, column: :embedding, filters: {})
          return [] unless pgvector_available?

          vector_string = "[#{embedding.join(',')}]"

          scope = model.all
          scope = scope.where(filters) if filters.any?

          results = scope.select(
            "#{model.table_name}.*",
            "#{quoted_column(column)} <=> '#{vector_string}' AS distance"
          ).order(Arel.sql("#{quoted_column(column)} <=> '#{vector_string}'"))
                         .limit(k)

          format_knn_response(results, model)
        end

        # Store an embedding for a record
        #
        # @param record [ActiveRecord::Base] The record to update
        # @param embedding [Array<Float>] The embedding vector
        # @param column [Symbol] The column to store the embedding
        #
        def store_embedding(record, embedding, column: :embedding)
          return false unless pgvector_available?

          vector_string = "[#{embedding.join(',')}]"
          record.update_column(column, vector_string)
        end

        # Batch store embeddings
        #
        # @param model [Class] The ActiveRecord model
        # @param embeddings [Hash<String, Array<Float>>] Map of ID -> embedding
        # @param column [Symbol] The column to store embeddings
        #
        def batch_store_embeddings(model, embeddings, column: :embedding)
          return 0 unless pgvector_available?

          # Use UPDATE FROM VALUES for efficient batch update
          values = embeddings.map do |id, emb|
            "(#{ActiveRecord::Base.connection.quote(id)}, '[#{emb.join(',')}]'::vector)"
          end.join(",")

          sql = <<~SQL.squish
            UPDATE #{model.table_name}
            SET #{column} = v.embedding
            FROM (VALUES #{values}) AS v(id, embedding)
            WHERE #{model.table_name}.id = v.id::uuid
          SQL

          ActiveRecord::Base.connection.execute(sql)
          embeddings.size
        rescue StandardError => e
          Rails.logger.error("Failed to batch store embeddings: #{e.message}")
          0
        end

        # Find similar records to a given record
        #
        # @param record [ActiveRecord::Base] The reference record
        # @param limit [Integer] Number of similar records
        # @param column [Symbol] Embedding column
        # @param exclude_self [Boolean] Exclude the reference record
        # @return [ActiveRecord::Relation]
        #
        def find_similar(record, limit: 10, column: :embedding, exclude_self: true)
          embedding = record.send(column)
          return record.class.none unless embedding && pgvector_available?

          scope = record.class.where.not(column => nil)
          scope = scope.where.not(id: record.id) if exclude_self

          vector_search(scope, embedding, column: column, limit: limit)
        end

        # Check if pgvector is available
        def pgvector_available?
          @pgvector_available ||= available_extensions.include?("vector")
        end

        private

        def distance_operator(metric)
          case metric
          when :l2, :euclidean
            "<->"  # L2/Euclidean distance
          when :inner_product
            "<#>"  # Negative inner product
          else
            "<=>"  # Cosine distance (default)
          end
        end

        def format_knn_response(records, model)
          hits = records.map do |record|
            {
              "_index" => model.table_name,
              "_id" => record.id.to_s,
              "_score" => 1.0 - (record.respond_to?(:distance) ? record.distance : 0),
              "_source" => record.as_json(except: [:distance])
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
      end
    end
  end
end
