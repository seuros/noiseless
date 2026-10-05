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
          MermaidDiagrams.ast_to_mermaid_flowchart(ast_node)
        when :mermaid_class
          MermaidDiagrams.ast_to_mermaid_class_diagram(ast_node)
        else
          raise ArgumentError, "Unsupported format: #{format}. Available: :tree, :json, :yaml, :mermaid, :mermaid_class"
        end
      end

      def self.explain_query_flow(ast_node, adapter)
        explanation = adapter.explain_query(ast_node)

        flow_diagram = MermaidDiagrams.generate_flow_diagram(explanation)

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
    end
  end
end
