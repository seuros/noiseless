# frozen_string_literal: true

require "test_helper"

class MultiMatchTest < ActiveSupport::TestCase
  def setup
    @model = Class.new do
      extend Noiseless::DSL::ClassMethods

      def self.name
        "TestModel"
      end

      def self.search_index
        ["test_models"]
      end
    end
  end

  def test_multi_match_ast_node
    multi_match = Noiseless::AST::MultiMatch.new("test query", %w[field1 field2])

    expected = {
      multi_match: {
        query: "test query",
        fields: %w[field1 field2]
      }
    }

    assert_equal expected, multi_match.to_hash
  end

  def test_multi_match_ast_node_with_options
    multi_match = Noiseless::AST::MultiMatch.new("test query", %w[field1 field2], type: "best_fields", boost: 2)

    expected = {
      multi_match: {
        query: "test query",
        fields: %w[field1 field2],
        type: "best_fields",
        boost: 2
      }
    }

    assert_equal expected, multi_match.to_hash
  end

  def test_query_builder_multi_match
    builder = Noiseless::QueryBuilder.new(@model)
    builder.multi_match("test query", %w[name description])

    ast = builder.to_ast

    assert_equal 1, ast.bool.must.size
    assert_instance_of Noiseless::AST::MultiMatch, ast.bool.must.first
    assert_equal "test query", ast.bool.must.first.query
    assert_equal %w[name description], ast.bool.must.first.fields
  end

  def test_query_builder_multi_match_with_options
    builder = Noiseless::QueryBuilder.new(@model)
    builder.multi_match("test query", %w[name description], type: "phrase", boost: 1.5)

    ast = builder.to_ast
    multi_match_node = ast.bool.must.first

    expected = {
      multi_match: {
        query: "test query",
        fields: %w[name description],
        type: "phrase",
        boost: 1.5
      }
    }

    assert_equal expected, multi_match_node.to_hash
  end

  def test_model_multi_match
    model_class = Class.new(Noiseless::Model) do
      extend Noiseless::DSL::ClassMethods

      def self.name
        "TestModel"
      end

      def self.search_index
        ["test_models"]
      end
    end

    model_instance = model_class.new
    result = model_instance.multi_match("test query", %w[name description])

    assert_equal model_instance, result

    ast = model_instance.to_ast
    assert_equal 1, ast.bool.must.size
    assert_instance_of Noiseless::AST::MultiMatch, ast.bool.must.first
  end

  def test_multi_match_with_single_field
    multi_match = Noiseless::AST::MultiMatch.new("test query", "name")

    expected = {
      multi_match: {
        query: "test query",
        fields: ["name"]
      }
    }

    assert_equal expected, multi_match.to_hash
  end

  def test_adapter_builds_multi_match_query
    adapter = Noiseless::Adapter.new

    # Create a bool node with a multi_match
    multi_match = Noiseless::AST::MultiMatch.new("test query", %w[name description])
    match = Noiseless::AST::Match.new("status", "active")
    bool_node = Noiseless::AST::Bool.new(must: [multi_match, match], filter: [])

    query_hash = adapter.send(:build_query_hash, bool_node)

    expected = {
      bool: {
        must: [
          {
            multi_match: {
              query: "test query",
              fields: %w[name description]
            }
          },
          {
            match: {
              "status" => "active"
            }
          }
        ]
      }
    }

    assert_equal expected, query_hash
  end
end
