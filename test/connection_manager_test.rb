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
      @connection_manager.register(:test, adapter: :elasticsearch, hosts: ["http://localhost:9200"])

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
end
