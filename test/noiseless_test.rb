# frozen_string_literal: true

require "test_helper"

class NoiselessTest < ActiveSupport::TestCase
  setup do
    # Reset configuration before each test
    Noiseless.config.connections_config = {}
    Noiseless.config.default_connection = :primary
    Noiseless.config.default_adapter = :elasticsearch
  end

  test "has default configuration values" do
    assert_equal :primary, Noiseless.config.default_connection
    assert_equal :elasticsearch, Noiseless.config.default_adapter
    assert_empty(Noiseless.config.connections_config)
  end

  test "allows configuration via block" do
    Noiseless.configure do |config|
      config.default_connection = :secondary
      config.default_adapter = :opensearch
    end

    assert_equal :secondary, Noiseless.config.default_connection
    assert_equal :opensearch, Noiseless.config.default_adapter
  end

  test "loads configuration from YAML file" do
    # Create temporary config file
    config_content = {
      "test" => {
        "default" => "test_connection",
        "connections" => {
          "test_connection" => {
            "adapter" => "elasticsearch",
            "host" => "localhost",
            "port" => 9200
          }
        }
      }
    }

    config_path = Rails.root.join("tmp/test_noiseless.yml")
    File.write(config_path, config_content.to_yaml)

    Noiseless.config.config_path = config_path
    Noiseless.load_configuration!

    assert_equal :test_connection, Noiseless.config.default_connection
    assert_equal "elasticsearch", Noiseless.config.connections_config[:test_connection][:adapter]
    assert_equal "localhost", Noiseless.config.connections_config[:test_connection][:host]
    assert_equal 9200, Noiseless.config.connections_config[:test_connection][:port]

    # Cleanup
    FileUtils.rm_f(config_path)
  end
end
