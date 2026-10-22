# frozen_string_literal: true

require "unit_test_helper"
require "active_record"

class PostgresqlSearchContractTest < SearchContractCase
  class RecordModel < ActiveRecord::Base
    self.abstract_class = true
  end

  def setup
    super
    raw = @adapter.raw_response
    @adapter = Noiseless::Adapters::Postgresql.new(skip_extension_check: true)
    # Keep PostgreSQL's real Async(finished: false) search wrapper, but no SQL.
    @adapter.define_singleton_method(:execute_search) { |*args, **options| raw }
  end

  def test_paginator_waits_for_the_postgresql_task
    with_search_client do
      paginator = Search.page(2).per(10)
      assert_equal 21, paginator.total_count
      assert_equal %w[2 1 99], paginator.to_a.map(&:id)

      Sync { assert_equal 21, Search.page(1).total_count }
    end
  end

  def test_multi_search_waits_for_the_postgresql_task
    with_search_client do
      response = Search.multi_search { |query| query.match(:name, "company") }
      assert_equal 21, response.total
      assert_equal 3, response.results_for_model(Search).size
    end
  end

  def test_postgresql_resolves_the_explicit_record_class_before_index_inference
    search_class = Class.new(Noiseless::Model)
    search_class.record_class RecordModel
    assert_equal RecordModel, @adapter.send(:resolve_model, ["unrelated_alias"], search_class)
    assert_equal RecordModel, @adapter.send(:resolve_model, ["unrelated_alias"], RecordModel)
  end
end
