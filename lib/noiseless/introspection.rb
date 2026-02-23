# frozen_string_literal: true

module Noiseless
  module Introspection
    # Runtime adapter and module detection
    def adapter_info
      {
        adapter_type: self.class.name.split("::").last.underscore.to_sym,
        execution_mode: :async,
        execution_module: detect_execution_module,
        capabilities: adapter_capabilities,
        engine_name: engine_name
      }
    end

    def detect_execution_module
      execution_modules = singleton_class.included_modules.select do |mod|
        mod.name&.include?("ExecutionModules") ||
          mod.name&.include?("Execution")
      end

      execution_modules.map do |mod|
        {
          name: mod.name,
          async: true
        }
      end
    end

    def adapter_capabilities
      capabilities = [:async_support]

      # Check for bulk operations
      capabilities << :bulk_operations if respond_to?(:bulk)

      # Check for search operations
      capabilities << :search if respond_to?(:search)

      # Check for index management
      capabilities << :index_management if respond_to?(:create_index)

      # Check for document operations
      capabilities << :document_operations if respond_to?(:index_document)

      # Engine-specific capabilities
      case self.class.name
      when /OpenSearch/
        capabilities += %i[point_in_time_search search_templates] if respond_to?(:point_in_time_search)
      when /Typesense/
        capabilities += %i[typo_tolerance faceted_search] if respond_to?(:faceted_search)
      when /Elasticsearch/
        capabilities += %i[aggregations percolate] if respond_to?(:percolate)
      end

      capabilities.uniq
    end

    def engine_name
      case self.class.name
      when /OpenSearch/ then :opensearch
      when /Elasticsearch/ then :elasticsearch
      when /Typesense/ then :typesense
      else :base
      end
    end

    # Query execution introspection
    def explain_query(ast_node, **)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      explanation = {
        adapter: adapter_info,
        ast: ast_node.to_h,
        engine_query: nil,
        execution_plan: [],
        performance: {}
      }

      # Convert AST to engine query
      conversion_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      engine_query = ast_to_hash(ast_node)
      conversion_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - conversion_start

      explanation[:engine_query] = engine_query
      explanation[:performance][:ast_conversion_ms] = (conversion_time * 1000).round(3)

      # Build execution plan
      explanation[:execution_plan] = build_execution_plan(ast_node, **)

      total_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      explanation[:performance][:total_explanation_ms] = (total_time * 1000).round(3)

      explanation
    end

    def build_execution_plan(_ast_node, **_opts)
      plan = []

      plan << {
        step: "ast_validation",
        description: "Validate AST structure",
        estimated_cost: "O(n) where n = AST node count"
      }

      plan << {
        step: "query_conversion",
        description: "Convert AST to #{engine_name} query format",
        estimated_cost: "O(n) where n = AST complexity"
      }

      plan << {
        step: "async_task_creation",
        description: "Wrap execution in Async::Task",
        estimated_cost: "O(1)"
      }

      plan << {
        step: "engine_execution",
        description: "Execute query on #{engine_name}",
        estimated_cost: "Variable - depends on query complexity and data size"
      }

      plan << {
        step: "response_processing",
        description: "Convert engine response to Noiseless format",
        estimated_cost: "O(m) where m = result count"
      }

      plan
    end

    # Cross-engine compatibility analysis
    def compatibility_matrix
      available_adapters = [
        Noiseless::Adapters::Elasticsearch,
        Noiseless::Adapters::OpenSearch,
        Noiseless::Adapters::Typesense
      ]

      matrix = {}

      available_adapters.each do |adapter_class|
        adapter = adapter_class.new
        adapter_name = adapter.engine_name

        matrix[:"#{adapter_name}_async"] = {
          available: true,
          capabilities: adapter.adapter_capabilities,
          engine_name: adapter.engine_name
        }
      rescue StandardError => e
        fallback_key = adapter_class.name.split("::").last.underscore
        matrix[:"#{fallback_key}_async"] = {
          available: false,
          error: e.message
        }
      end

      matrix
    end

    # Performance profiling
    def profile_query(ast_node, iterations: 100, **)
      results = {
        adapter: adapter_info,
        iterations: iterations,
        measurements: [],
        summary: {}
      }

      iterations.times do |_i|
        measurement = measure_single_execution(ast_node, **)
        results[:measurements] << measurement
      end

      # Calculate summary statistics
      times = results[:measurements].map { |m| m[:total_time_ms] }
      results[:summary] = {
        min_ms: times.min,
        max_ms: times.max,
        avg_ms: (times.sum / times.size).round(3),
        median_ms: times.sort[times.size / 2],
        std_dev_ms: calculate_std_dev(times).round(3)
      }

      results
    end

    private

    def measure_single_execution(ast_node, **_opts)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Convert AST
      conversion_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      _engine_query = ast_to_hash(ast_node)
      conversion_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - conversion_start

      # Execute (mock execution for testing)
      execution_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sleep(0.001) # Simulate async execution
      execution_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - execution_start

      total_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      {
        ast_conversion_ms: (conversion_time * 1000).round(3),
        execution_ms: (execution_time * 1000).round(3),
        total_time_ms: (total_time * 1000).round(3)
      }
    end

    def calculate_std_dev(values)
      return 0.0 if values.size <= 1

      mean = values.sum / values.size.to_f
      variance = values.sum { |v| (v - mean)**2 } / (values.size - 1).to_f
      Math.sqrt(variance)
    end
  end
end
