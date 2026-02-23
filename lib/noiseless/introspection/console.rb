# frozen_string_literal: true

module Noiseless
  module Introspection
    class Console
      def self.inspect_adapter(adapter)
        puts "[INSPECT] Adapter Introspection"
        puts "=" * 50

        info = adapter.adapter_info

        puts "Adapter Type: #{info[:adapter_type]}"
        puts "Execution Mode: #{info[:execution_mode]}"
        puts "Engine Name: #{info[:engine_name]}"
        puts "Capabilities: #{info[:capabilities].join(', ')}"

        puts "\nExecution Modules:"
        info[:execution_module].each do |mod|
          puts "  - #{mod[:name]}"
        end

        puts "\n#{'=' * 50}"
      end

      def self.compare_query_across_engines(ast_node, **)
        puts "[COMPARE] Cross-Engine Query Comparison"
        puts "=" * 60

        comparison = QueryVisualizer.compare_across_engines(ast_node, **)

        puts "Original AST:"
        puts JSON.pretty_generate(comparison[:original_ast])

        puts "\nEngine Translations:"
        comparison[:engine_translations].each do |engine, data|
          puts "\n#{engine.to_s.humanize}:"
          if data[:error]
            puts "  [ERROR] #{data[:error]}"
          else
            puts "  [OK] Available"
            puts "  Performance Score: #{data[:estimated_performance][:estimated_score]}"
            puts "  Query Differences: #{data[:query_differences].size} found"
          end
        end

        puts "\nCompatibility Analysis:"
        analysis = comparison[:compatibility_analysis]
        puts "  Compatible Engines: #{analysis[:compatible_engines].join(', ')}"
        puts "  Common Features: #{analysis[:common_features]&.join(', ') || 'None'}"

        if analysis[:potential_issues].any?
          puts "  [WARN] Potential Issues:"
          analysis[:potential_issues].each do |issue|
            puts "    - #{issue[:description]} (#{issue[:severity]})"
          end
        end

        puts "\nRecommendations:"
        comparison[:recommendations].each do |rec|
          puts "  [TIP] #{rec[:recommendation]}"
        end

        puts "\n#{'=' * 60}"
      end

      def self.visualize_ast(ast_node, format: :tree)
        puts "[AST] Visualization (#{format})"
        puts "=" * 40

        visualization = QueryVisualizer.visualize_ast(ast_node, format: format)
        puts visualization

        puts "=" * 40
      end

      def self.explain_query_execution(ast_node, adapter)
        puts "[EXPLAIN] Query Execution Explanation"
        puts "=" * 50

        flow_info = QueryVisualizer.explain_query_flow(ast_node, adapter)
        explanation = flow_info[:explanation]

        puts "Adapter: #{explanation[:adapter][:adapter_type]} (#{explanation[:adapter][:execution_mode]})"
        puts "Engine: #{explanation[:adapter][:engine_name]}"

        puts "\nExecution Plan:"
        explanation[:execution_plan].each_with_index do |step, index|
          puts "  #{index + 1}. #{step[:description]}"
          puts "     Cost: #{step[:estimated_cost]}"
        end

        puts "\nPerformance Breakdown:"
        flow_info[:performance_breakdown].each do |metric|
          puts "  #{metric[:metric]}: #{metric[:value]} #{metric[:unit]}"
        end

        if flow_info[:optimization_suggestions].any?
          puts "\nOptimization Suggestions:"
          flow_info[:optimization_suggestions].each do |suggestion|
            puts "  [TIP] #{suggestion[:suggestion]} (Impact: #{suggestion[:impact]})"
          end
        end

        puts "\n#{'=' * 50}"
      end

      def self.profile_query_performance(ast_node, adapter, iterations: 10)
        puts "[PROFILE] Query Performance Profile"
        puts "=" * 50

        puts "Running #{iterations} iterations on #{adapter.adapter_info[:adapter_type]} (#{adapter.adapter_info[:execution_mode]})..."

        profile = adapter.profile_query(ast_node, iterations: iterations)
        summary = profile[:summary]

        puts "\nPerformance Summary:"
        puts "  Minimum: #{summary[:min_ms]}ms"
        puts "  Maximum: #{summary[:max_ms]}ms"
        puts "  Average: #{summary[:avg_ms]}ms"
        puts "  Median: #{summary[:median_ms]}ms"
        puts "  Std Dev: #{summary[:std_dev_ms]}ms"

        # Show distribution
        puts "\nTime Distribution:"
        bins = create_histogram_bins(profile[:measurements].pluck(:total_time_ms))
        bins.each do |bin|
          bar = "█" * (bin[:count] * 50 / iterations)
          puts "  #{bin[:range]}: #{bar} (#{bin[:count]})"
        end

        puts "\n#{'=' * 50}"
      end

      def self.compatibility_matrix
        puts "[MATRIX] Adapter Compatibility Matrix"
        puts "=" * 60

        matrix = Noiseless::Adapter.new.compatibility_matrix

        matrix.each do |adapter_key, info|
          status = info[:available] ? "[OK]" : "[X]"
          name = adapter_key.to_s.humanize

          puts "#{status} #{name}"
          if info[:available]
            puts "    Engine: #{info[:engine_name]}"
            puts "    Capabilities: #{info[:capabilities].join(', ')}"
          else
            puts "    Error: #{info[:error]}"
          end
          puts
        end

        puts "=" * 60
      end

      def self.interactive_mode
        puts "[INTERACTIVE] Noiseless Interactive Introspection Mode"
        puts "Type 'help' for available commands or 'exit' to quit"
        puts "=" * 60

        loop do
          print "noiseless> "
          input = gets.chomp.strip

          case input
          when "help"
            show_help
          when "adapters"
            compatibility_matrix
          when "exit", "quit"
            puts "Goodbye!"
            break
          when /^profile\s+(.+)/
            # TODO: Parse query and run profile
            puts "Profile command not yet implemented"
          when /^compare\s+(.+)/
            # TODO: Parse query and run comparison
            puts "Compare command not yet implemented"
          else
            puts "Unknown command: #{input}. Type 'help' for available commands."
          end
        end
      end

      def self.create_histogram_bins(values, bin_count: 5)
        return [] if values.empty?

        min_val = values.min
        max_val = values.max
        bin_size = (max_val - min_val) / bin_count.to_f

        bins = Array.new(bin_count) do |i|
          range_start = min_val + (i * bin_size)
          range_end = min_val + ((i + 1) * bin_size)
          {
            range: "#{range_start.round(2)}-#{range_end.round(2)}ms",
            count: 0
          }
        end

        values.each do |value|
          bin_index = ((value - min_val) / bin_size).floor
          bin_index = [bin_index, bin_count - 1].min # Ensure we don't exceed bounds
          bins[bin_index][:count] += 1
        end

        bins
      end

      def self.show_help
        puts <<~HELP
          Available Commands:

          help         - Show this help message
          adapters     - Show adapter compatibility matrix
          exit/quit    - Exit interactive mode

          Coming Soon:
          profile <query>    - Profile query performance
          compare <query>    - Compare query across engines
          explain <query>    - Explain query execution
          visualize <query>  - Visualize AST structure
        HELP
      end
    end
  end
end
