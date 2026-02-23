# frozen_string_literal: true

require "test_helper"

class AdaptersTest < ActiveSupport::TestCase
  test "looks up adapters by name with dynamic class loading" do
    adapter = Noiseless::Adapters.lookup(:elasticsearch, hosts: ["http://localhost:9200"])
    assert_instance_of Noiseless::Adapters::Elasticsearch, adapter
  end

  test "looks up adapters with underscored names" do
    adapter = Noiseless::Adapters.lookup(:open_search, hosts: ["http://localhost:9200"])
    assert_instance_of Noiseless::Adapters::OpenSearch, adapter
  end

  test "raises error for unknown adapter" do
    error = assert_raises NameError do
      Noiseless::Adapters.lookup(:unknown_adapter)
    end
    assert_match(/uninitialized constant.*UnknownAdapter/, error.message)
  end
end
