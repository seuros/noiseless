# frozen_string_literal: true

module Noiseless
  module Adapters
    module ExecutionModules
      # Builds ActiveRecord scopes from the noiseless AST for the PostgreSQL adapter.
      module PostgresqlQuery
        DEFAULT_LIMIT = 20

        private

        def build_search_scope(model, query_hash)
          scope = model.all

          # Apply must clauses (full-text search)
          scope = apply_must_clauses(scope, query_hash[:bool]&.must || [], model)

          # Apply filter clauses (exact matches)
          scope = apply_filter_clauses(scope, query_hash[:bool]&.filter || [], model)

          # Apply sorting (pagination is applied by the caller, after counting)
          apply_sorting(scope, query_hash[:sort] || [], model)
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
                      apply_wildcard(scope, node, model)
                    when AST::Range
                      apply_range(scope, node, model)
                    when AST::Prefix
                      apply_prefix(scope, node, model)
                    else
                      scope
                    end
          end

          scope
        end

        def apply_match(scope, node, model)
          field = node.field.to_s
          value = node.value.to_s

          # Mapping-only fields (denormalized into a search index, not columns)
          # cannot be satisfied here; fail closed rather than matching everything.
          return scope.none unless column?(model, field)

          # Use pg_trgm similarity for fuzzy matching, accent-insensitive when
          # the unaccent extension is present.
          if trgm_available? && text_column?(model, field)
            scope.where(
              "#{fuzzy_column(field)} % #{fuzzy_param} OR " \
              "#{fuzzy_column(field)} ILIKE #{fuzzy_param}",
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
          # Drop mapping-only fields; if none of the requested fields are real
          # columns the query cannot be satisfied — fail closed.
          fields = node.fields.map(&:to_s).select { |field| column?(model, field) }
          return scope.none if fields.empty?

          conditions = fields.map do |field|
            if trgm_available? && text_column?(model, field)
              "(#{fuzzy_column(field)} % #{fuzzy_param} OR " \
                "#{fuzzy_column(field)} ILIKE #{fuzzy_param})"
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

        def apply_wildcard(scope, node, model = nil)
          field = node.field.to_s
          return scope.none if model && !column?(model, field)

          # Convert OpenSearch wildcards to SQL: * -> %, ? -> _
          pattern = node.value.to_s.tr("*", "%").tr("?", "_")

          scope.where("#{quoted_column(field)} ILIKE ?", pattern)
        end

        def apply_range(scope, node, model = nil)
          return scope.none if model && !column?(model, node.field.to_s)

          field = quoted_column(node.field.to_s)

          scope = scope.where("#{field} >= ?", node.gte) if node.gte
          scope = scope.where("#{field} <= ?", node.lte) if node.lte
          scope = scope.where("#{field} > ?", node.gt) if node.gt
          scope = scope.where("#{field} < ?", node.lt) if node.lt

          scope
        end

        def apply_prefix(scope, node, model = nil)
          return scope.none if model && !column?(model, node.field.to_s)

          scope.where("#{quoted_column(node.field.to_s)} ILIKE ?", "#{sanitize_like(node.value)}%")
        end

        def apply_filter_clauses(scope, filter_nodes, model = nil)
          return scope if filter_nodes.empty?

          filter_nodes.each do |node|
            value = node.value

            scope = if value.is_a?(Hash) && value.with_indifferent_access.key?(:geo_distance)
                      apply_geo_filter(scope, node, model)
                    elsif range_filter?(value)
                      apply_range(scope, AST::Range.new(node.field, **value.transform_keys(&:to_sym)), model)
                    elsif model && !column?(model, node.field.to_s)
                      # A filter on a mapping-only field cannot be enforced;
                      # silently dropping it would broaden results, so fail closed.
                      scope.none
                    elsif model && array_column?(model, node.field.to_s)
                      apply_array_filter(scope, node.field.to_s, value, model)
                    else
                      scope.where(node.field => value)
                    end
          end

          scope
        end

        def apply_array_filter(scope, field, value, model)
          cast = "#{model.columns_hash[field].sql_type.sub(/\[\]\z/, '')}[]"
          operator = value.is_a?(Array) ? "&&" : "@>"

          scope.where("#{quoted_column(field)} #{operator} ARRAY[?]::#{cast}", value)
        end

        # Requires PostGIS. A geo filter that cannot be enforced must narrow to
        # nothing: dropping it would return every row regardless of distance.
        def apply_geo_filter(scope, node, model = nil)
          field = node.field.to_s
          return scope.none if model && !column?(model, field)

          geo_config = node.value.with_indifferent_access[:geo_distance]
          return scope.none unless geo_config.is_a?(Hash)

          geo_point = geo_config.values.find { |v| v.is_a?(Hash) && v.key?(:lat) && v.key?(:lon) }
          return scope.none unless geo_point

          scope.where(
            "ST_DWithin(#{quoted_column(field)}::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)",
            Float(geo_point[:lon]),
            Float(geo_point[:lat]),
            parse_distance(geo_config[:distance])
          )
        rescue ArgumentError, TypeError => e
          Rails.logger.warn("Noiseless: geo filter on #{field} has invalid coordinates: #{e.message}")
          scope.none
        end

        def apply_sorting(scope, sort_nodes, model = nil)
          sorted_fields = []
          order_clauses = sort_nodes.filter_map do |node|
            field = node.field.to_s
            # Sorting on a mapping-only field is cosmetic — drop it instead of
            # erroring the whole query.
            next if model && !column?(model, field)

            sorted_fields << field
            direction = node.direction.to_s.upcase == "DESC" ? "DESC" : "ASC"
            "#{quoted_column(field)} #{direction}"
          end

          primary_key = model.respond_to?(:primary_key) ? model.primary_key : nil
          order_clauses << "#{quoted_column(primary_key)} ASC" if primary_key && !sorted_fields.include?(primary_key.to_s)
          return scope if order_clauses.empty?

          scope.order(Arel.sql(order_clauses.join(", ")))
        end

        def apply_pagination(scope, paginate_node)
          page = paginate_node&.page || 1
          per_page = paginate_node&.per_page || DEFAULT_LIMIT

          offset = (page - 1) * per_page

          scope.limit(per_page).offset(offset)
        end

        def trgm_available?
          @trgm_available ||= available_extensions.include?("pg_trgm")
        end

        def unaccent_available?
          @unaccent_available ||= available_extensions.include?("unaccent")
        end

        def column?(model, field)
          model.columns_hash.key?(field.to_s)
        end

        def text_column?(model, field)
          column = model.columns_hash[field.to_s]
          column && %i[string text citext].include?(column.type) && !array_column?(model, field)
        end

        def array_column?(model, field)
          column = model.columns_hash[field.to_s]
          column.respond_to?(:array) && column.array
        end

        def range_filter?(value)
          value.is_a?(Hash) && value.any? && (value.keys.map(&:to_sym) - Noiseless::Adapter::RANGE_OPERATORS).empty?
        end

        def fuzzy_column(field)
          unaccent_available? ? "unaccent(#{quoted_column(field)})" : quoted_column(field)
        end

        def fuzzy_param
          unaccent_available? ? "unaccent(?)" : "?"
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
      end
    end
  end
end
