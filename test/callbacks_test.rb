# frozen_string_literal: true

require "test_helper"

# Regression coverage for search error handling.
#
# Noiseless talks to HTTP backends over an Async::HTTP transport, which raises
# socket/system errors (e.g. Errno::ECONNREFUSED) when the cluster is
# unreachable. Those are wrapped at the transport boundary into
# Noiseless::ConnectionError so callers rescue a single semantic error instead
# of enumerating HTTP-stack-specific exception classes.
#
# On the auto-index path that wrapped error must NOT abort the host record's
# save/commit unless the model opts into `auto_index(raise_on_error: true)`.
class CallbacksTest < ActiveSupport::TestCase
  Transport = Noiseless::Adapters::ExecutionModules::HttpTransport

  # Indexable model that swallows search errors (default behaviour).
  class LenientArticle < ApplicationRecord
    self.table_name = "articles"
    include Noiseless::Callbacks

    auto_index enabled: true

    def to_search_hash
      { id: id, title: title, content: content, author: author, status: status }
    end

    # Defined so tests can stub it; the real method comes from
    # Noiseless::DSL::InstanceMethods in production.
    def document_manager(**)
      nil
    end
  end

  # Indexable model that re-raises search errors.
  class StrictArticle < ApplicationRecord
    self.table_name = "articles"
    include Noiseless::Callbacks

    auto_index enabled: true, raise_on_error: true

    def to_search_hash
      { id: id, title: title, content: content, author: author, status: status }
    end

    def document_manager(**)
      nil
    end
  end

  # Document manager double that fails the way the wrapped transport does.
  class UnreachableDocumentManager
    def update_document(**)
      raise Noiseless::ConnectionError, "search backend unreachable"
    end

    def delete_document(**)
      raise Noiseless::ConnectionError, "search backend unreachable"
    end
  end

  def lenient_record
    LenientArticle.new(title: "t", content: "c", author: "a", status: "draft")
  end

  def strict_record
    StrictArticle.new(title: "t", content: "c", author: "a", status: "draft")
  end

  test "ConnectionError is a Noiseless::Error" do
    assert Noiseless::ConnectionError < Noiseless::Error
  end

  test "transport wraps a refused connection in Noiseless::ConnectionError" do
    host = "http://127.0.0.1:1"
    refusing_client = Object.new
    def refusing_client.get(*)
      raise Errno::ECONNREFUSED, "Connection refused - connect(2) for 127.0.0.1:1"
    end

    transport = Object.new.extend(Transport)
    transport.instance_variable_set(:@hosts, [host])
    transport.instance_variable_set(:@clients, { host => refusing_client })

    error = assert_raises(Noiseless::ConnectionError) { transport.send(:get_request, "/") }
    assert_instance_of Errno::ECONNREFUSED, error.cause, "original error preserved as cause"
  end

  test "update callback swallows an unreachable backend by default" do
    record = lenient_record
    record.stub(:document_manager, UnreachableDocumentManager.new) do
      assert_nothing_raised { record.send(:update_search_index_on_commit) }
    end
  end

  test "delete callback swallows an unreachable backend by default" do
    record = lenient_record
    record.stub(:document_manager, UnreachableDocumentManager.new) do
      assert_nothing_raised { record.send(:remove_from_search_index_on_commit) }
    end
  end

  test "raise_on_error: true propagates the search error" do
    record = strict_record
    record.stub(:document_manager, UnreachableDocumentManager.new) do
      assert_raises(Noiseless::ConnectionError) { record.send(:update_search_index_on_commit) }
    end
  end
end
