# frozen_string_literal: true

module Noiseless
  module Adapters
    module ExecutionModules
      # Translates the noiseless AST into Typesense search parameters.
      module TypesenseQuery
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
      end
    end
  end
end
