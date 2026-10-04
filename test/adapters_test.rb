# frozen_string_literal: true

require "test_helper"

class AdaptersTest < ActiveSupport::TestCase
  test "looks up adapters by name with dynamic class loading" do
    adapter = Noiseless::Adapters.lookup(:elasticsearch, hosts: ["http://localhost:9201"])
    assert_instance_of Noiseless::Adapters::Elasticsearch, adapter
  end

  test "looks up adapters with underscored names" do
    adapter = Noiseless::Adapters.lookup(:open_search, hosts: ["http://localhost:9202"])
    assert_instance_of Noiseless::Adapters::OpenSearch, adapter
  end

  test "raises error for unknown adapter" do
    error = assert_raises NameError do
      Noiseless::Adapters.lookup(:unknown_adapter)
    end
    assert_match(/uninitialized constant.*UnknownAdapter/, error.message)
  end

  test "IndicesAPI#get resolves the public index_exists? task" do
    adapter = Struct.new(:exists) { def index_exists?(_index) = Async { exists } }

    assert_equal({ "a" => {} }, Sync { Noiseless::Adapters::IndicesAPI.new(adapter.new(true)).get(index: "a") })
    assert_raises(Noiseless::Error) { Sync { Noiseless::Adapters::IndicesAPI.new(adapter.new(false)).get(index: "a") } }
  end

  test "inspect never prints connection credentials" do
    manager = Noiseless::ConnectionManager.new
    manager.register(:ts, adapter: :typesense, hosts: ["http://localhost:8108"], api_key: "s3cret")

    assert_not_includes manager.inspect, "s3cret"
    assert_not_includes manager.client(:ts).inspect, "s3cret"
  end
end
