# frozen_string_literal: true

require "unit_test_helper"

class SearchPaginationTest < SearchContractCase
  def test_pagination_waits_and_caches_the_response
    with_search_client do
      paginator = Search.page(2).per(10)

      assert_equal 21, paginator.total_count
      assert_equal %w[2 1 99], paginator.to_a.map(&:id)
      assert_equal 3, paginator.size
      assert_equal 3, paginator.total_pages
      assert_equal 3, paginator.next_page
      assert_equal 1, paginator.prev_page
      assert_equal 3, paginator.took
      assert_equal 1, @adapter.calls.size
      assert_equal 10, @adapter.calls.first[:query][:from]
      assert_equal 10, @adapter.calls.first[:query][:size]
    end
  end

  def test_pagination_also_works_inside_an_async_context
    with_search_client do
      Sync do
        paginator = Search.page(1).per(10)
        assert_equal %w[2 1 99], paginator.map(&:id)
        assert_equal 21, paginator.total_count
      end
    end
  end

  def test_empty_search_is_not_an_error
    @adapter.raw_response["hits"] = { "total" => 0, "hits" => [] }
    with_search_client do
      paginator = Search.page(1)
      assert_empty paginator.to_a
      assert_equal 0, paginator.total_count
    end
  end

  def test_backend_errors_propagate_and_do_not_cache_a_failed_search
    @adapter.error = Noiseless::SearchError.new("backend rejected query")
    with_search_client do
      paginator = Search.page(1)
      assert_raises(Noiseless::SearchError) { paginator.total_count }
      @adapter.error = nil
      assert_equal 21, paginator.total_count
      assert_equal 2, @adapter.calls.size
    end
  end
end
