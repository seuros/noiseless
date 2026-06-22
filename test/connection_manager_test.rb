# frozen_string_literal: true

require "test_helper"

class ConnectionManagerTest < ActiveSupport::TestCase
  setup do
    @connection_manager = Noiseless::ConnectionManager.new
  end

  test "registers and retrieves clients with hosts array" do
    # Mock adapter
    mock_adapter = Minitest::Mock.new
    mock_adapter.expect :==, true, [mock_adapter]

    Noiseless::Adapters.stub :lookup, mock_adapter do
      @connection_manager.register(:test, adapter: :elasticsearch, hosts: ["http://localhost:9201"])

      client = @connection_manager.client(:test)
      assert_equal mock_adapter, client
    end

    mock_adapter.verify
  end

  test "raises error for unknown connection" do
    error = assert_raises RuntimeError do
      @connection_manager.client(:unknown)
    end
    assert_match(/Unknown connection: unknown/, error.message)
  end

  test "forwards configured timeout to adapter lookup" do
    captured = nil
    fake_lookup = lambda do |_adapter, **params|
      captured = params
      Object.new
    end

    Noiseless::Adapters.stub :lookup, fake_lookup do
      @connection_manager.register(:test, adapter: :opensearch, hosts: ["http://localhost:9200"], timeout: 3)
      @connection_manager.client(:test)
    end

    assert_equal 3, captured[:timeout]
    assert_equal ["http://localhost:9200"], captured[:hosts]
  end

  test "omits timeout from lookup when not configured so transport default applies" do
    captured = nil
    fake_lookup = lambda do |_adapter, **params|
      captured = params
      Object.new
    end

    Noiseless::Adapters.stub :lookup, fake_lookup do
      @connection_manager.register(:test, adapter: :opensearch, hosts: ["http://localhost:9200"])
      @connection_manager.client(:test)
    end

    refute_includes captured.keys, :timeout
  end
end
