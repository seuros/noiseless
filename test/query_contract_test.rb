# frozen_string_literal: true

require "unit_test_helper"

class QueryContractTest < SearchContractCase
  class RecordingBuilder
    attr_reader :arguments, :options, :block

    def clause(*arguments, **options, &block)
      @arguments = arguments
      @options = options
      @block = block
      :builder_return_value
    end
  end

  class Wrapper
    extend Noiseless::QueryDelegation
    delegate_query_methods :clause, to: :@builder

    def initialize(builder)
      @builder = builder
    end
  end

  def test_fluent_delegation_preserves_arguments_keywords_blocks_and_receiver
    builder = RecordingBuilder.new
    wrapper = Wrapper.new(builder)
    block = -> { :aggregation }

    assert_same wrapper, wrapper.clause(:name, { boost: 2 }, fuzziness: 1, &block)
    assert_equal [:name, { boost: 2 }], builder.arguments
    assert_equal({ fuzziness: 1 }, builder.options)
    assert_same block, builder.block
  end

  def test_model_delegation_builds_the_expected_ast
    search = Search.new
    assert_same search, search.range(:price, gte: 10).sort(:name).paginate(page: 2, per_page: 7)
    assert_same search, search.aggregation(:names, :terms, field: :name) { agg(:max_price, :max, field: :price) }

    ast = search.to_ast
    assert_equal 10, ast.bool.must.first.gte
    assert_equal :asc, ast.sort.first.direction
    assert_equal 7, ast.paginate.per_page
    assert_equal "max_price", ast.aggregations.first.sub_aggregations.first.name
  end

  def test_wrappers_keep_their_existing_public_query_methods
    search = Search.new
    multi = Search.multi_search
    paginator = Search.page(1)

    assert_respond_to search, :range
    refute_respond_to search, :vector
    refute_respond_to multi, :range
    refute_respond_to multi, :vector
    assert_respond_to paginator, :vector
    refute_respond_to paginator, :limit
  end

  def test_multi_search_keeps_positional_pagination
    with_search_client do
      multi = Search.multi_search
      assert_same multi, multi.paginate(3, 7)
      response = multi.search
      assert_equal 14, @adapter.calls.first[:query][:from]
      assert_equal 7, @adapter.calls.first[:query][:size]
      assert_equal 3, response.current_page
    end
  end

  def test_index_resolution_is_shared_by_the_builder_and_registry
    plural = Class.new(Noiseless::Model) do
      def self.name = "QueryContractTest::PluralSearch"
      search_index "first", "second"
      index_name "ignored"
    end
    fallback = Class.new(Noiseless::Model) do
      def self.name = "QueryContractTest::LibraryEntry"
    end
    registry = Noiseless::ModelRegistry.send(:new)

    { Search => ["contract_companies"], plural => %w[first second], fallback => ["library_entries"] }.each do |model, indexes|
      assert_equal indexes, Noiseless::QueryBuilder.indexes_for(model)
      assert_equal indexes, Noiseless::QueryBuilder.new(model).to_ast.indexes
      assert_equal indexes.first, Noiseless::BulkImporter.new(model, connection: :contract).send(:index_name)
      assert_equal indexes.first, Noiseless::DocumentManager.new(model.new, connection: :contract).send(:index_name)
      registry.register(model)
      indexes.each { assert_equal [model], registry.models_for_index(it) }
    end
    assert_empty Noiseless::QueryBuilder.indexes_for(nil)
  end

  def test_pagination_conversion_is_shared_by_both_adapter_paths
    postgres = Noiseless::Adapters::Postgresql.new(skip_extension_check: true)
    { nil => { from: 0, size: 20 }, Noiseless::AST::Paginate.new(3, 7) => { from: 14, size: 7 } }.each do |node, expected|
      assert_equal expected, Noiseless::Pagination.query_options(node)
      assert_equal expected, @adapter.send(:build_pagination_hash, node)
      assert_equal expected, postgres.send(:build_pagination_hash, node)
    end
  end
end
