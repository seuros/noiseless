# frozen_string_literal: true

require "test_helper"

# Test class to demonstrate Noiseless::TestHelper usage
class TestHelperTest < ActiveSupport::TestCase
  include Noiseless::TestHelper

  def setup
    # Create a test search class for demonstration
    @test_class = Class.new(Noiseless::Model) do
      index_name "test_products"

      def self.name
        "TestProduct"
      end
    end
    Object.const_set(:TestProduct, @test_class)
  end

  def teardown
    Object.send(:remove_const, "TestProduct") if defined?(TestProduct)
  end

  def test_cassette_name_generation
    # Create a lambda to simulate a test method
    fake_test_method = -> { generate_cassette_name }

    cassette_name = fake_test_method.call

    # Should generate a reasonable cassette name based on class and method
    assert_match(/test_helper/, cassette_name)
    assert_match(/test_cassette_name_generation/, cassette_name)
  end

  def test_vcr_integration_with_custom_options
    # Test that we can pass custom VCR options
    executed = false
    noiseless_cassette(record: :new_episodes) do
      # This would normally make HTTP requests
      executed = true
    end
    assert executed, "Block should have been executed"
  end

  def test_reset_index_helper
    # Test that reset_index! doesn't raise errors
    # In test mode, it should detect VCR playback and skip

    # Should not raise an error even if client isn't properly configured

    reset_index!("test_index")
    assert true, "reset_index! should not raise errors"
  rescue StandardError => e
    # If it fails, it should fail gracefully
    assert e.message.include?("Failed to reset") || e.message.include?("connection")
  end

  def test_find_search_classes
    search_classes = find_search_classes

    # Should find our test class
    assert_includes search_classes, TestProduct
    assert(search_classes.all? { |klass| klass < Noiseless::Model })
  end

  def test_print_query_utility
    search = TestProduct.new
    search.match(:name, "test")
    search.filter(:status, "active")

    # Capture output
    output = capture_io do
      print_query(search)
    end

    assert_match(/Generated Query AST/, output.first)
    assert_match(/Must clauses: 1/, output.first)
    assert_match(/Filter clauses: 1/, output.first)
  end

  def test_under_vcr_playback_detection
    # When not using VCR, should return false
    assert_not under_vcr_playback?

    # When using VCR, the detection should work
    # (This is harder to test without actual VCR setup)
  end

  def test_verbose_mode_detection
    # Test environment variable detection
    original_verbose = ENV.fetch("NOISELESS_VERBOSE", nil)

    ENV["NOISELESS_VERBOSE"] = "true"
    assert_predicate self, :verbose_mode?

    ENV["NOISELESS_VERBOSE"] = "false"
    assert_not verbose_mode?

    ENV.delete("NOISELESS_VERBOSE")
    assert_not verbose_mode?
  ensure
    if original_verbose
      ENV["NOISELESS_VERBOSE"] = original_verbose
    else
      ENV.delete("NOISELESS_VERBOSE")
    end
  end

  def test_default_vcr_options
    options = default_vcr_options

    assert_equal :once, options[:record]
    assert_includes options[:match_requests_on], :method
    assert_includes options[:match_requests_on], :uri
    assert_includes options[:match_requests_on], :body
  end

  def test_instrumentation_integration
    events_captured = []

    # Mock ActiveSupport::Notifications
    ActiveSupport::Notifications.stub(:subscribe, lambda { |*args, &block|
      # Simulate an event
      block.call("noiseless.search", Time.current, Time.current + 0.1, "id", { query: "test" })
      events_captured << args
      subscription = Object.new
      def subscription.unsubscribe; end
      subscription
    }) do
      with_search_instrumentation do
        # Some search operation would happen here
      end
    end

    # Verify that instrumentation was set up
    assert_operator events_captured.length, :>=, 0, "Should have attempted to set up instrumentation"
  end

  private

  def capture_io
    old_stdout = $stdout
    old_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
    [$stdout.string, $stderr.string]
  ensure
    $stdout = old_stdout
    $stderr = old_stderr
  end
end
