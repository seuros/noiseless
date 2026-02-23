# frozen_string_literal: true

require "test_helper"

class OpenSearchMultiMatchTest < ActiveSupport::TestCase
  def os_url
    host = ENV.fetch("OPENSEARCH_HOST", "localhost")
    port = ENV.fetch("OPENSEARCH_PORT", "9201")
    "http://#{host}:#{port}"
  end

  def setup
    @model = Class.new do
      extend Noiseless::DSL::ClassMethods

      def self.name
        "OpenSearchTestModel"
      end

      def self.search_index
        ["opensearch_test_models"]
      end
    end
  end

  def test_opensearch_adapter_builds_multi_match_query
    adapter = Noiseless::Adapters::OpenSearch.new

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

  def test_opensearch_adapter_builds_multi_match_with_options
    adapter = Noiseless::Adapters::OpenSearch.new

    # Create a bool node with a multi_match with OpenSearch-specific options
    multi_match = Noiseless::AST::MultiMatch.new(
      "test query",
      ["name^2", "description", "content"],
      type: "best_fields",
      operator: "and",
      minimum_should_match: "75%"
    )
    bool_node = Noiseless::AST::Bool.new(must: [multi_match], filter: [])

    query_hash = adapter.send(:build_query_hash, bool_node)

    expected = {
      bool: {
        must: [
          {
            multi_match: {
              query: "test query",
              fields: ["name^2", "description", "content"],
              type: "best_fields",
              operator: "and",
              minimum_should_match: "75%"
            }
          }
        ]
      }
    }

    assert_equal expected, query_hash
  end

  def test_async_opensearch_adapter_builds_multi_match_query
    adapter = Noiseless::Adapters::OpenSearch.new(hosts: [os_url])

    # Create a bool node with a multi_match
    multi_match = Noiseless::AST::MultiMatch.new("async test query", %w[title body])
    bool_node = Noiseless::AST::Bool.new(must: [multi_match], filter: [])

    query_hash = adapter.send(:build_query_hash, bool_node)

    expected = {
      bool: {
        must: [
          {
            multi_match: {
              query: "async test query",
              fields: %w[title body]
            }
          }
        ]
      }
    }

    assert_equal expected, query_hash
  end

  def test_opensearch_vs_elasticsearch_compatibility
    opensearch_adapter = Noiseless::Adapters::OpenSearch.new
    elasticsearch_adapter = Noiseless::Adapters::Elasticsearch.new

    # Create identical multi_match query
    multi_match = Noiseless::AST::MultiMatch.new(
      "compatibility test",
      %w[title content],
      type: "phrase_prefix",
      boost: 1.5
    )
    bool_node = Noiseless::AST::Bool.new(must: [multi_match], filter: [])

    opensearch_query = opensearch_adapter.send(:build_query_hash, bool_node)
    elasticsearch_query = elasticsearch_adapter.send(:build_query_hash, bool_node)

    # Both should generate identical queries (OpenSearch is Elasticsearch-compatible)
    assert_equal elasticsearch_query, opensearch_query
  end

  def test_opensearch_supports_advanced_multi_match_features
    adapter = Noiseless::Adapters::OpenSearch.new

    # Test advanced OpenSearch multi_match features
    multi_match = Noiseless::AST::MultiMatch.new(
      "advanced search",
      ["title^3", "description^2", "content"],
      type: "cross_fields",
      analyzer: "standard",
      fuzziness: "AUTO",
      prefix_length: 2,
      max_expansions: 50,
      operator: "and"
    )
    bool_node = Noiseless::AST::Bool.new(must: [multi_match], filter: [])

    query_hash = adapter.send(:build_query_hash, bool_node)

    multi_match_query = query_hash[:bool][:must].first[:multi_match]

    assert_equal "advanced search", multi_match_query[:query]
    assert_equal ["title^3", "description^2", "content"], multi_match_query[:fields]
    assert_equal "cross_fields", multi_match_query[:type]
    assert_equal "standard", multi_match_query[:analyzer]
    assert_equal "AUTO", multi_match_query[:fuzziness]
    assert_equal 2, multi_match_query[:prefix_length]
    assert_equal 50, multi_match_query[:max_expansions]
    assert_equal "and", multi_match_query[:operator]
  end
end
