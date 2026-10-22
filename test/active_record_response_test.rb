# frozen_string_literal: true

require "unit_test_helper"
require "active_record"

class ActiveRecordResponseTest < SearchContractCase
  # A separate pool keeps the Rails dummy app's database configuration intact.
  class Database < ActiveRecord::Base
    self.abstract_class = true
  end

  class Company < Database
    self.table_name = "record_contract_companies"
  end

  class Search < Noiseless::Model
    index_name "company_search_alias_v2"
    connection :contract
    record_class "ActiveRecordResponseTest::Company"
  end

  def setup
    super
    Database.establish_connection(adapter: "sqlite3", database: ":memory:")
    Database.connection.create_table(:record_contract_companies) { |table| table.string :name }
    Company.create!(id: 1, name: "First")
    Company.create!(id: 2, name: "Second")
    @adapter.raw_response["hits"]["hits"].each { it["_index"] = Search.index_name }
  end

  def teardown
    Database.remove_connection
    super
  end

  def test_public_search_loads_real_records_once_in_hit_order
    with_search_client do
      response = Search.search_sync(response_type: :records) { |query| query.paginate(page: 2, per_page: 10) }
      queries = []
      subscriber = lambda do |event|
        sql = event.payload[:sql]
        queries << sql if sql.start_with?("SELECT") && sql.include?(Company.table_name)
      end

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        assert_equal [2, 1], response.to_a.map(&:id)
        assert_equal %w[Second First], response.to_a.map(&:name)
        assert_equal [[2, "2"], [1, "1"]], response.map_with_hit { |record, hit| [record.id, hit["_id"]] }
      end

      assert_equal 1, queries.size
      assert_equal 21, response.to_a.total_count
      assert_equal 2, response.to_a.current_page
      assert_equal 10, response.to_a.per_page
    end
  end

  def test_instance_search_loads_records_inside_an_async_context
    with_search_client do
      Sync do
        response = Search.new.match(:name, "company").execute_sync(response_type: :records)
        assert_equal [2, 1], response.to_a.map(&:id)
        assert response.to_a.all? { it.is_a?(Company) }
      end
    end
  end

  def test_adapter_still_accepts_a_direct_active_record_model
    ast = Noiseless::QueryBuilder.new(Search).to_ast
    response = Sync { @adapter.search(ast, model_class: Company).wait }
    assert_instance_of Noiseless::Response::Records, response
    assert_equal [2, 1], response.to_a.map(&:id)
  end

  def test_multi_search_loads_real_records_through_the_explicit_mapping
    with_search_client do
      response = Search.multi_search { |query| query.match(:name, "company") }
      assert_equal [2, 1], response.records_for_model(Search).map(&:id)
      assert_equal 3, response.results_for_model(Search).size
      assert_equal 21, response.total
    end
  end
end
