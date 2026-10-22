# frozen_string_literal: true

require "unit_test_helper"

class MultiSearchTest < SearchContractCase
  def test_global_search_waits_and_unwraps_the_response
    with_search_client do
      response = Noiseless.multi_search(indexes: ["contract_companies"], models: [Search], connection: :contract) do |query|
        query.match(:name, "company")
        query.paginate(page: 2, per_page: 10)
      end

      assert_instance_of Noiseless::MultiSearchResponse, response
      assert_equal 21, response.total
      assert_equal 3, response.hits.size
      assert_equal 3, response.took
      assert_equal 2, response.current_page
      assert_equal 3, response.total_pages
      assert_equal ["contract_companies"], @adapter.calls.first[:indexes]
    end
  end

  def test_search_class_api_uses_index_name_and_groups_hits
    with_search_client do
      response = Search.multi_search { |query| query.match(:name, "company") }

      assert_equal ["contract_companies"], @adapter.calls.first[:indexes]
      assert_equal 3, response.results_for_model(Search).size
      assert_equal({ Search.name.to_sym => 3 }, response.model_counts)
    end
  end

  def test_chainable_search_works_inside_an_async_context
    with_search_client do
      Sync do
        search = Search.multi_search(models: [Search, OtherSearch])
        response = search.match(:name, "company").limit(5).search

        assert_equal 21, response.total
        assert_equal %w[contract_companies contract_articles], @adapter.calls.first[:indexes]
        assert_equal 5, @adapter.calls.first[:query][:size]
      end
    end
  end

  def test_explicit_indexes_override_model_indexes
    with_search_client do
      Search.multi_search(indexes: ["company_alias"]) do |query|
        query.indexes(["not_the_requested_index"])
        query.match(:name, "company")
      end
      assert_equal ["company_alias"], @adapter.calls.first[:indexes]
    end
  end

  def test_multi_model_record_loading_uses_explicit_mappings
    with_search_client do
      response = MappedSearch.multi_search { |query| query.match(:name, "company") }
      assert_equal [2, 1], response.records_for_model(MappedSearch).map(&:id)
      assert_equal [2, 1], response.records_for_model(MappedSearch).map(&:id)
      assert_equal [%w[2 1 99]], RecordModel.queries
    end
  end

  def test_grouping_only_uses_requested_models
    @adapter.raw_response["hits"]["hits"] << { "_index" => "contract_articles", "_id" => "5", "_source" => {} }
    with_search_client do
      response = Search.multi_search { |query| query.match(:name, "company") }
      assert_equal [Search.name.to_sym], response.results_by_model.keys
      assert_empty response.results_for_model(OtherSearch)
    end
  end

  def test_global_search_defaults_to_registered_searchable_models
    with_search_client do
      Noiseless.stub(:searchable_models, [Search, OtherSearch]) do
        response = Noiseless.multi_search(connection: :contract) { |query| query.match(:name, "company") }
        assert_equal %w[contract_companies contract_articles], @adapter.calls.first[:indexes]
        assert_equal 3, response.results_for_model(Search).size
      end
    end
  end

  def test_empty_response_and_backend_errors
    with_search_client do
      @adapter.raw_response["hits"] = { "total" => 0, "hits" => [] }
      response = Search.multi_search { |query| query.match(:name, "missing") }
      assert_equal 0, response.total
      assert_empty response.results_by_model

      @adapter.error = Noiseless::SearchError.new("backend rejected query")
      assert_raises(Noiseless::SearchError) { Search.multi_search { |query| query.match(:name, "company") } }
    end
  end
end
