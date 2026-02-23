# frozen_string_literal: true

require "minitest"
require "async"
require "set" # rubocop:disable Lint/RedundantRequireStatement
require_relative "test_helper"

module Noiseless
  # The Ultimate Search Test Case
  #
  # Automatically includes TestHelper and provides seamless VCR integration.
  # Every test method automatically gets its own VCR cassette.
  #
  # Usage:
  #   class Search::ProductTest < Noiseless::TestCase
  #     def test_searching_by_name
  #       # Automatically uses cassette: search/product/searching_by_name
  #       results = Search::Product.by_name("Ruby").execute
  #       assert results.any?
  #     end
  #
  #     def test_with_custom_options
  #       # Override VCR options for this test
  #       noiseless_cassette(record: :new_episodes) do
  #         results = Search::Product.featured.execute
  #         assert results.any?
  #       end
  #     end
  #   end
  class TestCase < Minitest::Test
    include Noiseless::TestHelper

    # 🎭 Auto-wrap every test method with VCR cassette
    def self.method_added(method_name)
      return unless method_name.to_s.start_with?("test_")
      return if @__noiseless_wrapped_methods&.include?(method_name)

      # Track wrapped methods to avoid infinite recursion
      @__noiseless_wrapped_methods ||= Set.new
      @__noiseless_wrapped_methods << method_name

      # Store original method
      original_method = instance_method(method_name)

      # Remove original method
      remove_method(method_name)

      # Define wrapped method
      define_method(method_name) do
        # Generate cassette name based on class and method
        cassette_name = generate_test_cassette_name(method_name)

        # Auto-wrap with VCR cassette, passing the actual test method name
        noiseless_cassette(cassette_name: cassette_name, test_method: method_name) do
          original_method.bind_call(self)
        end
      end

      super
    end

    # 🏗️ Test setup and teardown
    def setup
      super
      setup_noiseless_test_environment
    end

    def teardown
      cleanup_noiseless_test_environment
      super
    end

    private

    def generate_test_cassette_name(method_name)
      # Extract test class path (e.g., "Search::ProductTest" -> "search/product")
      class_path = self.class.name
                       .gsub(/Test$/, "")
                       .underscore
                       .gsub("::", "/")

      # Extract method name (e.g., "test_searching_products" -> "searching_products")
      clean_method_name = method_name.to_s.gsub(/^test_/, "")

      "#{class_path}/#{clean_method_name}"
    end

    def setup_noiseless_test_environment
      # Set verbose mode if requested
      @original_verbose = ENV.fetch("NOISELESS_VERBOSE", nil)

      # Ensure test-friendly configuration
      configure_test_connections if respond_to?(:configure_test_connections)

      # Print test start info if verbose
      puts "\n[TEST] Starting: #{self.class.name}##{name}" if verbose_mode?
    end

    def cleanup_noiseless_test_environment
      # Restore original verbose setting
      if @original_verbose
        ENV["NOISELESS_VERBOSE"] = @original_verbose
      else
        ENV.delete("NOISELESS_VERBOSE")
      end

      # Print test completion info if verbose
      puts "[PASS] Completed: #{self.class.name}##{name}" if verbose_mode?
    end

    # Enhanced cassette method with auto-naming
    def noiseless_cassette(options = {}, **kwargs, &)
      # Use the provided cassette name or generate one from test context
      # Parent method (TestHelper#noiseless_cassette) will handle the actual VCR setup
      super
    end

    # 🔧 Test-specific configuration helpers
    def configure_test_connections
      # Override in subclasses to set up test-specific connections
      # Example:
      # Noiseless.configure do |config|
      #   config.connections_config[:test] = {
      #     adapter: :elasticsearch,
      #     hosts: ['http://localhost:9201']
      #   }
      # end
    end

    # Enhanced assertion helpers
    def assert_search_results(search, expected_count = nil, message = nil)
      # Noiseless is now 100% async - execute returns Async::Task
      results = if search.respond_to?(:execute)
                  task = search.execute
                  Sync { task.wait }
                else
                  search
                end

      assert results.respond_to?(:size) || results.respond_to?(:count),
             "Expected search results to be enumerable, got #{results.class}"

      result_count = results.respond_to?(:size) ? results.size : results.count

      if expected_count
        assert_equal expected_count, result_count,
                     message || "Expected #{expected_count} results, got #{result_count}"
      else
        assert result_count.positive?,
               message || "Expected search results to not be empty"
      end
    end

    def assert_search_empty(search, message = nil)
      # Noiseless is now 100% async - execute returns Async::Task
      results = if search.respond_to?(:execute)
                  task = search.execute
                  Sync { task.wait }
                else
                  search
                end
      result_count = results.respond_to?(:size) ? results.size : results.count

      assert_equal 0, result_count,
                   message || "Expected search results to be empty, got #{result_count}"
    end

    def assert_search_includes(search, expected_item, message = nil)
      # Noiseless is now 100% async - execute returns Async::Task
      results = if search.respond_to?(:execute)
                  task = search.execute
                  Sync { task.wait }
                else
                  search
                end

      assert results.respond_to?(:include?) || results.respond_to?(:any?),
             "Expected search results to be enumerable"

      if results.respond_to?(:include?)
        assert results.include?(expected_item),
               message || "Expected search results to include #{expected_item}"
      else
        assert results.any?(expected_item),
               message || "Expected search results to include #{expected_item}"
      end
    end

    # 🚀 Performance assertion helpers
    def assert_search_performance(search, max_duration_ms = 1000)
      start_time = Time.current

      result = if block_given?
                 yield
               elsif search.respond_to?(:execute)
                 # Noiseless is now 100% async - execute returns Async::Task
                 task = search.execute
                 Sync { task.wait }
               else
                 search
               end

      duration_ms = ((Time.current - start_time) * 1000).round(2)

      assert duration_ms <= max_duration_ms,
             "Expected search to complete within #{max_duration_ms}ms, took #{duration_ms}ms"

      puts "[PERF] Search completed in #{duration_ms}ms (limit: #{max_duration_ms}ms)" if verbose_mode?

      result
    end

    # 🎯 Data setup helpers
    class << self
      def setup_test_data(index_name, records, adapter: :primary)
        define_method :setup do
          super()
          seed_data!(index_name, records, adapter: adapter) unless under_vcr_playback?
        end
      end

      def reset_test_indexes(*index_names)
        define_method :setup do
          super()
          index_names.each { |name| reset_index!(name) } unless under_vcr_playback?
        end
      end
    end
  end
end
