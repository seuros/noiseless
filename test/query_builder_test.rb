# frozen_string_literal: true

require "test_helper"

class QueryBuilderTest < ActiveSupport::TestCase
  setup do
    @model = Class.new(Noiseless::Model) do
      def self.name
        "TestModel"
      end
    end
  end

  test "builds AST from query methods" do
    builder = Noiseless::QueryBuilder.new(@model)
    builder.match("title", "Ruby")
           .filter("status", "published")
           .sort("created_at", :desc)
           .paginate(page: 2, per_page: 25)

    ast = builder.to_ast

    assert_instance_of Noiseless::AST::Root, ast
    assert_equal ["test_models"], ast.indexes
    assert_equal 1, ast.bool.must.size
    assert_equal 1, ast.bool.filter.size
    assert_equal 1, ast.sort.size
    assert_equal 2, ast.paginate.page
    assert_equal 25, ast.paginate.per_page
  end

  test "allows dynamic index specification" do
    builder = Noiseless::QueryBuilder.new(@model)
    builder.indexes(%w[custom_index another_index])

    ast = builder.to_ast
    assert_equal %w[custom_index another_index], ast.indexes
  end

  test "stores typesense union search options in AST" do
    builder = Noiseless::QueryBuilder.new(@model)
    builder.match("title", "Ruby")
           .remove_duplicates
           .facet_sample_slope(2.5)
           .pinned_hits({ "doc_1" => 1, "doc_2" => 2 })

    ast = builder.to_ast

    assert_equal true, ast.remove_duplicates
    assert_equal 2.5, ast.facet_sample_slope
    assert_equal "doc_1:1,doc_2:2", ast.pinned_hits
  end

  test "normalizes pinned_hits array format" do
    builder = Noiseless::QueryBuilder.new(@model)
    builder.pinned_hits([["doc_1", 1], ["doc_2", 2]])

    ast = builder.to_ast
    assert_equal "doc_1:1,doc_2:2", ast.pinned_hits
  end

  test "raises for invalid pinned_hits array entries" do
    builder = Noiseless::QueryBuilder.new(@model)

    assert_raises(ArgumentError) do
      builder.pinned_hits(["doc_1"])
    end
  end
end
