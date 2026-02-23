# frozen_string_literal: true

require "vcr"

module Noiseless
  # The Ultimate Search Testing Experience
  #
  # Provides automatic VCR cassette management, index reset helpers,
  # debug utilities, and seamless test integration for Noiseless searches.
  #
  # Usage:
  #   class MySearchTest < Minitest::Test
  #     include Noiseless::TestHelper
  #
  #     def test_searching_products
  #       noiseless_cassette do
  #         results = Search::Product.by_name("Ruby").execute
  #         assert results.any?
  #       end
  #     end
  #   end
  #
  # Or even simpler:
  #   class MySearchTest < Noiseless::TestCase
  #     def test_searching_products
  #       results = Search::Product.by_name("Ruby").execute
  #       assert results.any?
  #     end
  #   end
  module TestHelper
    def self.included(base)
      base.extend(ClassMethods)
      setup_vcr_configuration
    end

    def self.setup_vcr_configuration
      return if @vcr_configured

      require "webmock"
      WebMock.disable_net_connect!(allow_localhost: true)

      VCR.configure do |config|
        config.cassette_library_dir = "test/cassettes"
        config.hook_into :webmock
        config.default_cassette_options = {
          record: :once,
          match_requests_on: %i[method uri body]
        }

        # Allow HTTP connections when no cassette is in use (local only in CI)
        config.allow_http_connections_when_no_cassette = !ENV["CI"]

        # Ignore localhost and CI service hostname connections for tests
        config.ignore_hosts "localhost", "127.0.0.1", "0.0.0.0",
                            "elasticsearch", "opensearch", "typesense", "postgres"

        # Filter sensitive data - disabled for localhost testing
        # config.filter_sensitive_data('<OPENSEARCH_HOST>') do |interaction|
        #   uri = URI(interaction.request.uri)
        #   # Only filter non-localhost hosts to avoid test issues
        #   uri.host unless %w[localhost 127.0.0.1 0.0.0.0].include?(uri.host)
        # end
      end

      @vcr_configured = true
    end

    # Auto-VCR Integration
    # Automatically generates cassette names from test class and method
    def noiseless_cassette(options = {}, **kwargs, &)
      # Use provided cassette name or generate one
      cassette_name = kwargs[:cassette_name] || generate_cassette_name(test_method: kwargs[:test_method])

      # Extract VCR options from the hash
      vcr_options = options.except(:cassette_name, :test_method)
      vcr_options = default_vcr_options.merge(vcr_options)

      instrument_test_execution(cassette_name) do
        VCR.use_cassette(cassette_name, vcr_options, &)
      end
    end

    # Alternative method name for those who prefer it
    alias use_noiseless_cassette noiseless_cassette

    # 🔧 Index Management Helpers
    def reset_index!(index_name, adapter: :primary)
      return if under_vcr_playback?

      client = Noiseless.connections.client(adapter)
      client.indices.delete(index: index_name) if client.indices.exists(index: index_name)
      puts "[RESET] Reset index: #{index_name}" if verbose_mode?
    rescue StandardError => e
      warn "[WARN] Failed to reset index #{index_name}: #{e.message}" if verbose_mode?
    end

    def reset_all_indexes!(adapter: :primary)
      return if under_vcr_playback?

      # Find all registered search classes
      search_classes = find_search_classes
      search_classes.each do |klass|
        reset_index!(klass.index_name, adapter: adapter) if klass.respond_to?(:index_name) && klass.index_name
      end
      puts "[RESET] Reset all indexes (#{search_classes.size} classes)" if verbose_mode?
    end

    # Data Seeding Helpers
    def seed_data!(index_name, records, adapter: :primary)
      return if under_vcr_playback?

      client = Noiseless.connections.client(adapter)

      # Convert records to bulk format
      bulk_body = records.flat_map.with_index do |record, index|
        doc_id = record.respond_to?(:id) ? record.id : index
        [
          { index: { _index: index_name, _id: doc_id } },
          record.respond_to?(:to_h) ? record.to_h : record
        ]
      end

      response = client.bulk(body: bulk_body)

      # Refresh index to make documents searchable immediately
      client.indices.refresh(index: index_name)

      puts "[SEED] Seeded #{records.size} records to #{index_name}" if verbose_mode?
      response
    rescue StandardError => e
      warn "[WARN] Failed to seed data to #{index_name}: #{e.message}" if verbose_mode?
    end

    # Debug Utilities
    def print_curl(search_or_ast, adapter: :primary)
      return if under_vcr_playback?

      client = Noiseless.connections.client(adapter)
      ast = search_or_ast.respond_to?(:to_ast) ? search_or_ast.to_ast : search_or_ast

      # Convert AST to query hash
      query_hash = client.send(:ast_to_hash, ast)
      index_name = ast.indexes.first || "unknown_index"
      host = client.instance_variable_get(:@hosts).first

      # Generate curl command
      curl_command = build_curl_command(host, index_name, query_hash)

      puts "\n[CURL] Debug cURL Command:"
      puts "=" * 50
      puts curl_command
      puts "=" * 50

      curl_command
    end

    def print_query(search_or_ast)
      ast = search_or_ast.respond_to?(:to_ast) ? search_or_ast.to_ast : search_or_ast

      puts "\n[DEBUG] Generated Query AST:"
      puts "=" * 30
      puts "Indexes: #{ast.indexes}"
      puts "Must clauses: #{ast.bool.must.size}"
      puts "Filter clauses: #{ast.bool.filter.size}"
      puts "Sort clauses: #{ast.sort.size}"
      puts "Pagination: #{ast.paginate ? "#{ast.paginate.page}/#{ast.paginate.per_page}" : 'default'}"
      puts "=" * 30
    end

    # Test Instrumentation
    def with_search_instrumentation
      events = []
      subscription = ActiveSupport::Notifications.subscribe(/noiseless/) do |name, start, finish, _id, payload|
        events << {
          event: name,
          duration: ((finish - start) * 1000).round(2),
          payload: payload
        }
      end

      result = yield

      if verbose_mode? && events.any?
        puts "\n[EVENTS] Search Events:"
        events.each do |event|
          puts "   #{event[:event]}: #{event[:duration]}ms"
        end
      end

      result
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription) if subscription
    end

    private

    # 🏷️ Cassette Name Generation
    def generate_cassette_name(test_method: nil)
      # Extract test class path (e.g., "Search::ProductTest" -> "search/product")
      class_path = self.class.name
                       .gsub(/Test$/, "")
                       .underscore
                       .gsub("::", "/")

      # Use provided test method or find from call stack
      if test_method
        method_name = test_method.to_s.gsub(/^test_/, "")
      else
        # Extract method name from call stack, looking for test method
        test_method_name = find_test_method_name
        method_name = test_method_name.gsub(/^test_/, "") if test_method_name

        # Fallback to caller method if test method not found
        unless method_name
          caller_method = caller_locations(1, 1).first.label
          method_name = caller_method.gsub(/^test_/, "").gsub(/[^a-zA-Z0-9_]/, "_")
        end
      end

      "#{class_path}/#{method_name}"
    end

    def find_test_method_name
      # Look through call stack for test method
      caller_locations.each do |location|
        method_name = location.label
        return method_name if method_name&.start_with?("test_")
      end
      nil
    end

    def instrument_test_execution(cassette_name, &)
      start_time = Time.current

      puts "\n[VCR] Running test with cassette: #{cassette_name}" if verbose_mode?

      result = with_search_instrumentation(&)

      if verbose_mode?
        duration = ((Time.current - start_time) * 1000).round(2)
        puts "[DONE] Test completed in #{duration}ms"
      end

      result
    end

    def build_curl_command(host, index_name, query_hash)
      json_body = JSON.pretty_generate(query_hash)

      <<~CURL
        curl -X POST "#{host}/#{index_name}/_search" \\
             -H "Content-Type: application/json" \\
             -d '#{json_body}'
      CURL
    end

    def find_search_classes
      # Find all classes that inherit from Noiseless::Model
      ObjectSpace.each_object(Class).select do |klass|
        klass < Noiseless::Model
      rescue StandardError
        false
      end
    end

    def under_vcr_playback?
      VCR.current_cassette&.recording? == false
    rescue StandardError
      false
    end

    def verbose_mode?
      ENV["NOISELESS_VERBOSE"] == "true" || ENV["VERBOSE"] == "true"
    end

    def default_vcr_options
      {
        record: :once,
        match_requests_on: %i[method uri body],
        allow_unused_http_interactions: false
      }
    end

    module ClassMethods
      # 🎭 Class-level test helpers
      def reset_all_test_indexes!
        new.reset_all_indexes!
      end

      def seed_test_data!(index_name, records, adapter: :primary)
        new.seed_data!(index_name, records, adapter: adapter)
      end
    end
  end
end
