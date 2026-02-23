# frozen_string_literal: true

require_relative "test_helper"
require_relative "dummy/app/models/article"

class IntrospectionTest < ActiveSupport::TestCase
  def setup
    @search_model = Article::SearchFiction
  end

  def test_adapter_introspection
    adapter = Noiseless::Adapter.new
    info = adapter.adapter_info

    assert_equal :adapter, info[:adapter_type]
    assert_equal :async, info[:execution_mode]
    assert_equal :base, info[:engine_name]
    assert_includes info[:capabilities], :search
    assert_includes info[:capabilities], :bulk_operations
    assert_includes info[:capabilities], :async_support
  end

  def test_elasticsearch_adapter_introspection
    adapter = Noiseless::Adapters::Elasticsearch.new
    info = adapter.adapter_info

    assert_equal :elasticsearch, info[:adapter_type]
    assert_equal :elasticsearch, info[:engine_name]
    assert_includes info[:capabilities], :search
  end

  def test_opensearch_adapter_introspection
    adapter = Noiseless::Adapters::OpenSearch.new
    info = adapter.adapter_info

    assert_equal :open_search, info[:adapter_type]
    assert_equal :opensearch, info[:engine_name]
    assert_includes info[:capabilities], :search
  end

  def test_typesense_adapter_introspection
    adapter = Noiseless::Adapters::Typesense.new
    info = adapter.adapter_info

    assert_equal :typesense, info[:adapter_type]
    assert_equal :typesense, info[:engine_name]
    assert_includes info[:capabilities], :search
  end

  def test_query_explanation
    adapter = Noiseless::Adapters::Elasticsearch.new
    ast = build_sample_ast

    explanation = adapter.explain_query(ast)

    assert explanation.key?(:adapter)
    assert explanation.key?(:ast)
    assert explanation.key?(:engine_query)
    assert explanation.key?(:execution_plan)
    assert explanation.key?(:performance)

    assert_kind_of Array, explanation[:execution_plan]
    assert_operator explanation[:execution_plan].size, :>, 0
    assert explanation[:performance].key?(:ast_conversion_ms)
  end

  def test_query_performance_profiling
    adapter = Noiseless::Adapter.new
    ast = build_sample_ast

    profile = adapter.profile_query(ast, iterations: 5)

    assert_equal 5, profile[:iterations]
    assert_equal 5, profile[:measurements].size
    assert profile[:summary].key?(:avg_ms)
    assert profile[:summary].key?(:min_ms)
    assert profile[:summary].key?(:max_ms)
    assert_operator profile[:summary][:avg_ms], :>, 0
  end

  def test_cross_engine_query_comparison
    ast = build_sample_ast

    comparison = Noiseless::Introspection::QueryVisualizer.compare_across_engines(ast)

    assert comparison.key?(:original_ast)
    assert comparison.key?(:engine_translations)
    assert comparison.key?(:compatibility_analysis)
    assert comparison.key?(:recommendations)

    # Should have translations for all available engines
    translations = comparison[:engine_translations]
    assert translations.key?(:elasticsearch)
    assert translations.key?(:opensearch)
    assert translations.key?(:typesense)
  end

  def test_ast_visualization_tree_format
    ast = build_sample_ast

    visualization = Noiseless::Introspection::QueryVisualizer.visualize_ast(ast, format: :tree)

    assert_kind_of String, visualization
    assert_operator visualization.length, :>, 0
    # The visualization should contain some structure
    assert visualization.include?("indexes") || visualization.include?("bool") || visualization.include?("Root")
  end

  def test_ast_visualization_json_format
    ast = build_sample_ast

    visualization = Noiseless::Introspection::QueryVisualizer.visualize_ast(ast, format: :json)

    assert_kind_of String, visualization
    parsed = JSON.parse(visualization)
    assert parsed.key?("indexes")
  end

  def test_compatibility_matrix
    adapter = Noiseless::Adapter.new
    matrix = adapter.compatibility_matrix

    assert_kind_of Hash, matrix
    assert matrix.key?(:elasticsearch_async)
    assert matrix.key?(:opensearch_async)
    assert matrix.key?(:typesense_async)

    # Each entry should have availability info
    matrix.each do |key, info|
      assert info.key?(:available), "Missing :available key for #{key}"
      if info[:available]
        assert info.key?(:capabilities), "Missing :capabilities key for #{key}"
        assert info.key?(:engine_name), "Missing :engine_name key for #{key}"
      else
        assert info.key?(:error), "Missing :error key for #{key}"
      end
    end
  end

  def test_execution_module_detection
    adapter = Noiseless::Adapter.new

    modules = adapter.detect_execution_module

    assert_kind_of Array, modules

    modules.each do |mod|
      assert mod[:async]
    end
  end

  def test_query_flow_explanation
    adapter = Noiseless::Adapters::Elasticsearch.new
    ast = build_sample_ast

    flow_info = Noiseless::Introspection::QueryVisualizer.explain_query_flow(ast, adapter)

    assert flow_info.key?(:explanation)
    assert flow_info.key?(:visual_flow)
    assert flow_info.key?(:performance_breakdown)
    assert flow_info.key?(:optimization_suggestions)

    assert_includes flow_info[:visual_flow], "sequenceDiagram"
    assert_kind_of Array, flow_info[:performance_breakdown]
    assert_kind_of Array, flow_info[:optimization_suggestions]
  end

  def test_console_introspection_methods
    adapter = Noiseless::Adapter.new

    # Test that console methods don't raise errors and produce output
    output, _error = capture_io do
      Noiseless::Introspection::Console.inspect_adapter(adapter)
    end
    assert_operator output.length, :>, 0, "inspect_adapter should produce output"

    output, _error = capture_io do
      Noiseless::Introspection::Console.compatibility_matrix
    end
    assert_operator output.length, :>, 0, "compatibility_matrix should produce output"

    ast = build_sample_ast
    begin
      capture_io do
        Noiseless::Introspection::Console.visualize_ast(ast)
      end
    rescue StandardError => e
      flunk "visualize_ast raised an error: #{e.message}"
    end
  end

  private

  def build_sample_ast
    match = Noiseless::AST::Match.new("title", "search query")
    filter = Noiseless::AST::Filter.new("status", "published")
    bool_node = Noiseless::AST::Bool.new(must: [match], filter: [filter])

    Noiseless::AST::Root.new(
      indexes: ["articles"],
      bool: bool_node,
      sort: [],
      paginate: nil
    )
  end

  def capture_io
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
