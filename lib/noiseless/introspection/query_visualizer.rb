# frozen_string_literal: true

begin
  require "mermaid"
  DIAGRAMS_AVAILABLE = true
rescue LoadError
  DIAGRAMS_AVAILABLE = false
end

module Noiseless
  module Introspection
    class QueryVisualizer
      def self.compare_across_engines(ast_node, **_opts)
        adapters = [
          { name: :elasticsearch, class: Noiseless::Adapters::Elasticsearch },
          { name: :opensearch, class: Noiseless::Adapters::OpenSearch },
          { name: :typesense, class: Noiseless::Adapters::Typesense }
        ]

        comparison = {
          original_ast: ast_node.to_h,
          engine_translations: {},
          compatibility_analysis: {},
          recommendations: []
        }

        adapters.each do |adapter_config|
          adapter = adapter_config[:class].new

          # Get the translated query
          engine_query = adapter.send(:ast_to_hash, ast_node)

          # Get adapter info
          adapter_info = adapter.adapter_info

          comparison[:engine_translations][adapter_config[:name]] = {
            engine_query: engine_query,
            adapter_info: adapter_info,
            query_differences: analyze_query_differences(ast_node.to_h, engine_query),
            estimated_performance: estimate_performance(adapter_info, engine_query)
          }
        rescue StandardError => e
          comparison[:engine_translations][adapter_config[:name]] = {
            error: e.message,
            available: false
          }
        end

        # Analyze compatibility across engines
        comparison[:compatibility_analysis] = analyze_cross_engine_compatibility(comparison[:engine_translations])

        # Generate recommendations
        comparison[:recommendations] = generate_recommendations(comparison)

        comparison
      end

      def self.visualize_ast(ast_node, format: :tree)
        case format
        when :tree
          visualize_as_tree(ast_node.to_h)
        when :json
          JSON.pretty_generate(ast_node.to_h)
        when :yaml
          YAML.dump(ast_node.to_h)
        when :mermaid
          ast_to_mermaid_flowchart(ast_node)
        when :mermaid_class
          ast_to_mermaid_class_diagram(ast_node)
        else
          raise ArgumentError, "Unsupported format: #{format}. Available: :tree, :json, :yaml, :mermaid, :mermaid_class"
        end
      end

      def self.explain_query_flow(ast_node, adapter)
        explanation = adapter.explain_query(ast_node)

        flow_diagram = generate_flow_diagram(explanation)

        {
          explanation: explanation,
          visual_flow: flow_diagram,
          performance_breakdown: format_performance_breakdown(explanation[:performance]),
          optimization_suggestions: suggest_optimizations(explanation)
        }
      end

      def self.analyze_query_differences(original_ast, engine_query)
        differences = []

        # Check for field mapping differences
        original_fields = extract_fields_from_ast(original_ast)
        engine_fields = extract_fields_from_query(engine_query)

        if original_fields != engine_fields
          differences << {
            type: :field_mapping,
            original: original_fields,
            engine: engine_fields,
            impact: :medium
          }
        end

        # Check for query structure differences
        if has_structural_differences?(original_ast, engine_query)
          differences << {
            type: :structural_change,
            description: "Query structure adapted for engine compatibility",
            impact: :low
          }
        end

        differences
      end

      def self.estimate_performance(adapter_info, engine_query)
        base_score = 100

        # Adjust based on query complexity
        complexity_penalty = calculate_query_complexity(engine_query) * 5
        base_score -= complexity_penalty

        # Adjust based on adapter capabilities
        if adapter_info[:execution_mode] == :async
          base_score += 10 # Async generally better for I/O
        end

        # Engine-specific adjustments
        case adapter_info[:engine_name]
        when :typesense
          base_score += 15 # Generally faster for simple queries
        when :elasticsearch, :opensearch
          base_score += 5 # Good for complex queries
        end

        {
          estimated_score: [base_score, 0].max,
          factors: {
            complexity_penalty: complexity_penalty,
            async_bonus: adapter_info[:execution_mode] == :async ? 10 : 0,
            engine_factor: case adapter_info[:engine_name]
                           when :typesense then 15
                           when :elasticsearch, :opensearch then 5
                           else 0
                           end
          }
        }
      end

      def self.analyze_cross_engine_compatibility(translations)
        available_engines = translations.reject { |_, data| data.key?(:error) }

        analysis = {
          compatible_engines: available_engines.keys,
          query_variations: {},
          potential_issues: []
        }

        # Compare query structures across engines
        queries = available_engines.transform_values { |data| data[:engine_query] }

        if queries.values.uniq.size > 1
          analysis[:query_variations] = queries
          analysis[:potential_issues] << {
            type: :query_structure_differences,
            description: "Engines produce different query structures",
            severity: :medium
          }
        end

        # Check for feature compatibility
        features_by_engine = available_engines.transform_values do |data|
          data[:adapter_info][:capabilities]
        end

        common_features = features_by_engine.values.reduce(:&)
        analysis[:common_features] = common_features

        analysis
      end

      def self.generate_recommendations(comparison)
        recommendations = []

        # Performance recommendations
        best_performance = comparison[:engine_translations]
                           .reject { |_, data| data.key?(:error) }
                           .max_by { |_, data| data[:estimated_performance][:estimated_score] }

        if best_performance
          recommendations << {
            type: :performance,
            recommendation: "Consider using #{best_performance[0]} for optimal performance",
            score: best_performance[1][:estimated_performance][:estimated_score]
          }
        end

        # Compatibility recommendations
        if comparison[:compatibility_analysis][:potential_issues].any?
          recommendations << {
            type: :compatibility,
            recommendation: "Query may behave differently across engines",
            issues: comparison[:compatibility_analysis][:potential_issues]
          }
        end

        recommendations
      end

      def self.visualize_as_tree(node, depth = 0)
        indent = "  " * depth

        case node
        when Hash
          result = ""
          node.each do |key, value|
            result += "#{indent}#{key}:\n"
            result += visualize_as_tree(value, depth + 1)
          end
          result
        when Array
          result = ""
          node.each_with_index do |item, index|
            result += "#{indent}[#{index}]:\n"
            result += visualize_as_tree(item, depth + 1)
          end
          result
        else
          "#{indent}#{node}\n"
        end
      end

      def self.generate_mermaid_diagram(ast_node)
        diagram = "graph TD\n".dup

        add_node = lambda do |diagram, node, parent_id, counter|
          case node
          when Hash
            node.each do |key, value|
              current_id = "N#{counter[:count]}"
              counter[:count] += 1
              diagram << "  #{current_id}[#{key}]\n"
              diagram << "  #{parent_id} --> #{current_id}\n" if parent_id
              add_node.call(diagram, value, current_id, counter)
            end
          when Array
            node.each_with_index do |item, index|
              current_id = "N#{counter[:count]}"
              counter[:count] += 1
              diagram << "  #{current_id}[Item #{index}]\n"
              diagram << "  #{parent_id} --> #{current_id}\n" if parent_id
              add_node.call(diagram, item, current_id, counter)
            end
          else
            current_id = "N#{counter[:count]}"
            counter[:count] += 1
            diagram << "  #{current_id}[#{node}]\n"
            diagram << "  #{parent_id} --> #{current_id}\n" if parent_id
          end
        end

        counter = { count: 0 }
        root_id = "N#{counter[:count]}"
        counter[:count] += 1
        diagram << "  #{root_id}[Root]\n"

        add_node.call(diagram, ast_node.to_h, root_id, counter)
        diagram
      end

      def self.generate_flow_diagram(explanation)
        # Create a sequence diagram showing the query execution flow
        diagram = "sequenceDiagram\n".dup
        diagram << "    participant Client\n"
        diagram << "    participant Adapter\n"
        diagram << "    participant Engine\n"

        explanation[:execution_plan].each do |step|
          diagram << case step[:description]
                     when /validate/i
                       "    Client->>Adapter: #{step[:description]}\n"
                     when /convert/i, /format/i
                       "    Adapter->>Adapter: #{step[:description]}\n"
                     when /execute/i, /query/i
                       "    Adapter->>Engine: #{step[:description]}\n"
                     else
                       "    Engine->>Adapter: #{step[:description]}\n"
                     end
        end

        diagram << "    Adapter->>Client: Return results\n"
        diagram
      end

      def self.format_performance_breakdown(performance)
        performance.map do |metric, value|
          {
            metric: metric.to_s.humanize,
            value: value,
            unit: metric.to_s.end_with?("_ms") ? "milliseconds" : "unknown"
          }
        end
      end

      def self.suggest_optimizations(explanation)
        suggestions = []

        # Check for slow AST conversion
        if explanation[:performance][:ast_conversion_ms] > 1.0
          suggestions << {
            type: :performance,
            area: :ast_conversion,
            suggestion: "AST conversion is slow. Consider simplifying the query structure.",
            impact: :medium
          }
        end

        suggestions
      end

      # Helper methods
      def self.extract_fields_from_ast(ast)
        fields = []
        extract_recursive(ast, fields)
        fields.uniq
      end

      def self.extract_recursive(node, fields)
        case node
        when Hash
          fields << node["field"] if node["field"]
          fields << node[:field] if node[:field]
          node.each_value { |value| extract_recursive(value, fields) }
        when Array
          node.each { |item| extract_recursive(item, fields) }
        end
      end

      def self.extract_fields_from_query(_query)
        # This would need to be engine-specific
        # For now, return empty array
        []
      end

      def self.has_structural_differences?(ast, query)
        # Simple heuristic - if the query has different top-level keys
        ast_keys = ast.keys.sort
        query_keys = query.keys.sort
        ast_keys != query_keys
      end

      def self.calculate_query_complexity(query)
        complexity_counter = { count: 0 }
        count_recursive(query, complexity_counter)
        complexity_counter[:count]
      end

      def self.count_recursive(node, complexity)
        case node
        when Hash
          complexity[:count] += node.size
          node.each_value { |value| count_recursive(value, complexity) }
        when Array
          complexity[:count] += node.size
          node.each { |item| count_recursive(item, complexity) }
        end
      end

      # New methods using your diagram/mermaid gems
      def self.ast_to_mermaid_flowchart(ast_node)
        return "# Mermaid diagrams require 'diagrams' and 'mermaid' gems\n# Add to Gemfile: gem 'diagrams'; gem 'mermaid'" unless DIAGRAMS_AVAILABLE

        diagram = Diagrams::FlowchartDiagram.new(version: "1.0")

        # Convert AST structure to flowchart nodes and edges
        add_ast_node_to_flowchart(diagram, ast_node, "root")

        diagram.to_mermaid
      end

      def self.ast_to_mermaid_class_diagram(ast_node)
        return "# Mermaid diagrams require 'diagrams' and 'mermaid' gems\n# Add to Gemfile: gem 'diagrams'; gem 'mermaid'" unless DIAGRAMS_AVAILABLE

        diagram = Diagrams::ClassDiagram.new(version: "1.0")

        # Create a class representation of the AST structure
        root_class = Diagrams::Elements::ClassEntity.new(
          name: ast_node.class.name.split("::").last,
          attributes: ast_node.instance_variables.map do |var|
            "#{var.to_s.delete('@')}: #{ast_node.instance_variable_get(var).class.name.split('::').last}"
          end,
          methods: ast_node.public_methods(false).map { |method| "+#{method}()" }
        )

        diagram.add_class(root_class)

        # Add child nodes as related classes
        add_ast_children_to_class_diagram(diagram, ast_node, root_class.name)

        diagram.to_mermaid
      end

      def self.adapter_capability_matrix_to_mermaid
        return "# Mermaid diagrams require 'diagrams' and 'mermaid' gems\n# Add to Gemfile: gem 'diagrams'; gem 'mermaid'" unless DIAGRAMS_AVAILABLE

        # Create an ER diagram showing adapter capabilities
        diagram = Diagrams::ERDiagram.new

        # Add adapter entities
        diagram.add_entity(
          name: "ADAPTER",
          attributes: [
            { type: "string", name: "type", keys: [:PK] },
            { type: "string", name: "execution_mode" },
            { type: "string", name: "engine_name" }
          ]
        )

        diagram.add_entity(
          name: "CAPABILITY",
          attributes: [
            { type: "string", name: "name", keys: [:PK] },
            { type: "string", name: "description" }
          ]
        )

        diagram.add_entity(
          name: "ADAPTER_CAPABILITY",
          attributes: [
            { type: "string", name: "adapter_type", keys: %i[PK FK] },
            { type: "string", name: "capability_name", keys: %i[PK FK] }
          ]
        )

        # Add relationships
        diagram.add_relationship(
          entity1: "ADAPTER",
          entity2: "ADAPTER_CAPABILITY",
          cardinality1: :ONE_ONLY,
          cardinality2: :ZERO_OR_MORE,
          label: "has"
        )

        diagram.add_relationship(
          entity1: "CAPABILITY",
          entity2: "ADAPTER_CAPABILITY",
          cardinality1: :ONE_ONLY,
          cardinality2: :ZERO_OR_MORE,
          label: "provided by"
        )

        diagram.to_mermaid
      end

      def self.add_ast_node_to_flowchart(diagram, node, node_id)
        # Add current node
        flowchart_node = Diagrams::Elements::Node.new(
          id: node_id,
          label: node.class.name.split("::").last.to_s
        )
        diagram.add_node(flowchart_node)

        # Add child nodes and connect them
        return unless node.respond_to?(:instance_variables)

        node.instance_variables.each_with_index do |var, _index|
          child_value = node.instance_variable_get(var)

          if child_value.is_a?(Noiseless::AST::Node)
            child_id = "#{node_id}_#{var.to_s.delete('@')}"
            add_ast_node_to_flowchart(diagram, child_value, child_id)

            edge = Diagrams::Elements::Edge.new(
              source_id: node_id,
              target_id: child_id,
              label: var.to_s.delete("@")
            )
            diagram.add_edge(edge)
          elsif child_value.is_a?(Array) && child_value.any?(Noiseless::AST::Node)
            child_value.each_with_index do |item, item_index|
              next unless item.is_a?(Noiseless::AST::Node)

              child_id = "#{node_id}_#{var.to_s.delete('@')}_#{item_index}"
              add_ast_node_to_flowchart(diagram, item, child_id)

              edge = Diagrams::Elements::Edge.new(
                source_id: node_id,
                target_id: child_id,
                label: "#{var.to_s.delete('@')}[#{item_index}]"
              )
              diagram.add_edge(edge)
            end
          end
        end
      end

      def self.add_ast_children_to_class_diagram(diagram, node, parent_class_name)
        return unless node.respond_to?(:instance_variables)

        node.instance_variables.each do |var|
          child_value = node.instance_variable_get(var)

          next unless child_value.is_a?(Noiseless::AST::Node)

          child_class_name = child_value.class.name.split("::").last

          # Add child class if not already added
          unless diagram.classes.any? { |c| c.name == child_class_name }
            child_class = Diagrams::Elements::ClassEntity.new(
              name: child_class_name,
              attributes: child_value.instance_variables.map do |cv|
                "#{cv.to_s.delete('@')}: #{child_value.instance_variable_get(cv).class.name.split('::').last}"
              end
            )
            diagram.add_class(child_class)
          end

          # Add relationship
          relationship = Diagrams::Elements::Relationship.new(
            source_class_name: parent_class_name,
            target_class_name: child_class_name,
            type: "composition",
            label: var.to_s.delete("@")
          )
          diagram.add_relationship(relationship)

          # Recursively add children
          add_ast_children_to_class_diagram(diagram, child_value, child_class_name)
        end
      end
    end
  end
end
