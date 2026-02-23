# frozen_string_literal: true

require_relative "test_helper"
require "async"

class AsyncOperationsTest < ActiveSupport::TestCase
  def setup
    host = ENV.fetch("ELASTICSEARCH_HOST", "localhost")
    port = ENV.fetch("ELASTICSEARCH_PORT", "9200")
    @adapter = Noiseless::Adapters::Elasticsearch.new(hosts: ["http://#{host}:#{port}"])
  end

  def teardown
    @adapter.close if @adapter.respond_to?(:close)
  end

  def test_all_operations_return_async_tasks
    # All these operations should return Async::Task objects
    Sync do
      # Search operation
      ast = build_simple_ast
      search_task = @adapter.search(ast)
      assert_kind_of Async::Task, search_task, "search should return Async::Task"

      # Bulk operation
      bulk_task = @adapter.bulk([{ index: { _index: "test", _id: 1, data: { title: "test" } } }])
      assert_kind_of Async::Task, bulk_task, "bulk should return Async::Task"

      # Create index
      create_task = @adapter.create_index("test_index")
      assert_kind_of Async::Task, create_task, "create_index should return Async::Task"

      # Delete index
      delete_task = @adapter.delete_index("test_index")
      assert_kind_of Async::Task, delete_task, "delete_index should return Async::Task"

      # Index document
      index_doc_task = @adapter.index_document(index: "test", id: 1, document: { title: "test" })
      assert_kind_of Async::Task, index_doc_task, "index_document should return Async::Task"

      # Update document
      update_task = @adapter.update_document(index: "test", id: 1, changes: { title: "updated" })
      assert_kind_of Async::Task, update_task, "update_document should return Async::Task"

      # Delete document
      delete_doc_task = @adapter.delete_document(index: "test", id: 1)
      assert_kind_of Async::Task, delete_doc_task, "delete_document should return Async::Task"

      # Wait for all tasks to complete
      [search_task, bulk_task, create_task, delete_task,
       index_doc_task, update_task, delete_doc_task].each(&:wait)
    end
  end

  def test_exists_methods_should_be_async
    skip "exists? methods need to be wrapped in Async blocks"

    Sync do
      # These should also be async but currently aren't
      index_exists = @adapter.index_exists?("test")
      assert_kind_of Async::Task, index_exists, "index_exists? should return Async::Task"

      doc_exists = @adapter.document_exists?(index: "test", id: 1)
      assert_kind_of Async::Task, doc_exists, "document_exists? should return Async::Task"
    end
  end

  def test_concurrent_operations
    Sync do
      # Test that multiple operations can run concurrently
      start_time = Time.zone.now

      tasks = Array.new(10) do |i|
        @adapter.index_document(
          index: "test",
          id: i,
          document: { title: "Document #{i}" }
        )
      end

      # All tasks should be Async::Task objects
      tasks.each { |task| assert_kind_of Async::Task, task }

      # Wait for all to complete
      results = tasks.map(&:wait)

      elapsed = Time.zone.now - start_time

      # All results should be hashes
      results.each { |result| assert_kind_of Hash, result }

      # Operations should have run concurrently (time should be less than sequential)
      # This is a heuristic test - actual time depends on the backend
      assert_operator elapsed, :<, 5, "Concurrent operations took too long: #{elapsed}s"
    end
  end

  def test_connection_pooling
    # Test that HTTP clients are properly initialized
    assert @adapter.instance_variable_get(:@clients), "Adapter should have HTTP clients"

    clients = @adapter.instance_variable_get(:@clients)
    assert_kind_of Hash, clients
    assert_predicate clients, :any?, "Should have at least one HTTP client"

    clients.each do |host, client|
      assert_kind_of String, host
      assert_kind_of Async::HTTP::Client, client
    end
  end

  def test_async_http_client_usage
    # Ensure we're using Async::HTTP, not Net::HTTP
    assert_not @adapter.methods.include?(:make_http_request),
               "Should not have old Net::HTTP make_http_request method"

    assert_includes @adapter.private_methods, :with_client,
                    "Should have with_client method for Async::HTTP"
  end

  private

  def build_simple_ast
    match = Noiseless::AST::Match.new("title", "test")
    bool_node = Noiseless::AST::Bool.new(must: [match], filter: [])
    Noiseless::AST::Root.new(
      indexes: ["test"],
      bool: bool_node,
      sort: [],
      paginate: nil
    )
  end
end
