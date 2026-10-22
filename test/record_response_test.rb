# frozen_string_literal: true

require "unit_test_helper"

class RecordResponseTest < SearchContractCase
  def test_resolution_distinguishes_search_classes_from_record_models
    assert_same RecordModel, Noiseless::RecordClassResolver.resolve(MappedSearch)
    assert_same RecordModel, Noiseless::RecordClassResolver.resolve(RecordModel)
    assert_nil Noiseless::RecordClassResolver.resolve(Search)
    assert_nil Noiseless::RecordClassResolver.resolve(nil)

    # An unrelated class's similarly named method is not our search DSL.
    direct_model = Class.new(RecordModel) do
      def self.record_class = raise("Not a search class")
    end
    assert_same direct_model, Noiseless::RecordClassResolver.resolve(direct_model)
  end

  def test_search_class_without_a_record_loader_raises_even_when_empty
    with_search_client do
      [@adapter.raw_response["hits"], { "total" => 0, "hits" => [] }].each do |hits|
        @adapter.raw_response["hits"] = hits
        error = assert_raises(ArgumentError) do
          Search.search_sync(response_type: :records) { |query| query.match(:name, "company") }
        end
        assert_match(/record_class/, error.message)
      end
    end
  end

  def test_class_and_instance_search_load_records_in_hit_order
    search_class = Class.new(Search)
    search_class.index_name "company_alias_v2"
    search_class.connection :contract
    search_class.record_class RecordModel

    with_search_client do
      responses = [
        search_class.search_sync(response_type: :records) { |query| query.paginate(page: 2, per_page: 10) },
        search_class.new.paginate(page: 2, per_page: 10).execute_sync(response_type: :records)
      ]
      responses.each do |response|
        assert_equal [2, 1], response.to_a.map(&:id)
        assert_equal 21, response.to_a.total_count
        assert_equal 2, response.to_a.current_page
        assert_equal 10, response.to_a.per_page
        assert_equal [[2, "2"], [1, "1"]], response.map_with_hit { |record, hit| [record.id, hit["_id"]] }
      end
      assert_equal [%w[2 1 99], %w[2 1 99]], RecordModel.queries
    end
  end

  def test_configuring_record_class_does_not_change_the_default_response_type
    search_class = Class.new(Search)
    search_class.index_name "contract_companies"
    search_class.connection :contract
    search_class.record_class RecordModel

    with_search_client do
      task = search_class.search { |query| query.match(:name, "company") }
      assert_kind_of Async::Task, task
      assert_instance_of Noiseless::Response::Results, task.wait
      assert_empty RecordModel.queries
    end
  end

  def test_record_class_is_inherited_and_string_names_are_resolved_lazily
    parent = Class.new(Noiseless::Model)
    parent.record_class "NotLoadedYet"
    assert_raises(NameError) { parent.record_class }
    parent.record_class "SearchContractCase::RecordModel"
    child = Class.new(parent)

    assert_equal RecordModel, child.record_class
    child.record_class "String"
    assert_equal String, child.record_class
    assert_equal RecordModel, parent.record_class
    assert_raises(ArgumentError) { child.record_class Object.new }
    assert_raises(ArgumentError) { child.record_class false }
    assert_raises(ArgumentError) { Noiseless::Response::Records.new(@adapter.raw_response, child) }
  end

  def test_direct_record_models_still_work_and_empty_hits_do_not_query
    response = Noiseless::ResponseFactory.create(@adapter.raw_response, model_class: RecordModel)
    assert_instance_of Noiseless::Response::Records, response
    assert_equal [2, 1], response.to_a.map(&:id)
    assert_equal 1, RecordModel.queries.size
    assert_equal [2, 1], response.to_a.map(&:id)
    assert_equal 1, RecordModel.queries.size

    RecordModel.queries.clear
    @adapter.raw_response["hits"] = { "total" => 0, "hits" => [] }
    assert_empty Noiseless::Response::Records.new(@adapter.raw_response, RecordModel).to_a
    assert_empty RecordModel.queries
  end

  def test_string_mapping_does_not_cache_a_reloaded_record_class
    search_class = Class.new(Noiseless::Model)
    search_class.record_class "RecordResponseTest::ReloadableRecord"
    first = self.class.const_set(:ReloadableRecord, Class.new)
    assert_same first, search_class.record_class

    self.class.send(:remove_const, :ReloadableRecord)
    replacement = self.class.const_set(:ReloadableRecord, Class.new)
    assert_same replacement, search_class.record_class
  ensure
    self.class.send(:remove_const, :ReloadableRecord) if self.class.const_defined?(:ReloadableRecord, false)
  end
end
