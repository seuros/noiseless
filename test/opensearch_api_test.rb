# frozen_string_literal: true

require "test_helper"

class OpenSearchAPITest < ActiveSupport::TestCase
  def setup
    @adapter = Noiseless::Adapters::OpenSearch.new
  end

  # ============================================
  # PipelinesAPI Tests
  # ============================================

  def test_pipelines_api_accessible
    assert_respond_to @adapter, :pipelines
    assert_instance_of Noiseless::Adapters::OpenSearch::PipelinesAPI, @adapter.pipelines
  end

  def test_pipelines_api_create_method
    assert_respond_to @adapter.pipelines, :create
    assert_respond_to @adapter.pipelines, :put
  end

  def test_pipelines_api_get_method
    assert_respond_to @adapter.pipelines, :get
  end

  def test_pipelines_api_list_method
    assert_respond_to @adapter.pipelines, :list
    assert_respond_to @adapter.pipelines, :all
  end

  def test_pipelines_api_delete_method
    assert_respond_to @adapter.pipelines, :delete
  end

  def test_pipelines_api_exists_method
    assert_respond_to @adapter.pipelines, :exists?
  end

  # ============================================
  # RulesAPI Tests
  # ============================================

  def test_rules_api_accessible
    assert_respond_to @adapter, :rules
    assert_instance_of Noiseless::Adapters::OpenSearch::RulesAPI, @adapter.rules
  end

  def test_rules_api_create_method
    assert_respond_to @adapter.rules, :create
    assert_respond_to @adapter.rules, :put
  end

  def test_rules_api_get_method
    assert_respond_to @adapter.rules, :get
  end

  def test_rules_api_list_method
    assert_respond_to @adapter.rules, :list
    assert_respond_to @adapter.rules, :all
  end

  def test_rules_api_delete_method
    assert_respond_to @adapter.rules, :delete
  end

  def test_rules_api_exists_method
    assert_respond_to @adapter.rules, :exists?
  end

  # ============================================
  # Execution Methods Tests (private methods - check via private_methods)
  # ============================================

  def test_pipeline_execution_methods_exist
    # Private methods in execution module
    private_methods = @adapter.private_methods
    assert_includes private_methods, :execute_create_pipeline
    assert_includes private_methods, :execute_get_pipeline
    assert_includes private_methods, :execute_list_pipelines
    assert_includes private_methods, :execute_delete_pipeline
    assert_includes private_methods, :execute_pipeline_exists?
  end

  def test_rules_execution_methods_exist
    # Private methods in execution module
    private_methods = @adapter.private_methods
    assert_includes private_methods, :execute_create_rule
    assert_includes private_methods, :execute_get_rule
    assert_includes private_methods, :execute_list_rules
    assert_includes private_methods, :execute_delete_rule
    assert_includes private_methods, :execute_rule_exists?
  end

  # ============================================
  # ClusterAPI Tests (existing)
  # ============================================

  def test_cluster_api_accessible
    assert_respond_to @adapter, :cluster
    assert_instance_of Noiseless::Adapters::OpenSearch::ClusterAPI, @adapter.cluster
  end

  def test_cluster_api_health_method
    assert_respond_to @adapter.cluster, :health
  end

  # ============================================
  # IndicesAPI Tests (existing)
  # ============================================

  def test_indices_api_accessible
    assert_respond_to @adapter, :indices
    assert_instance_of Noiseless::Adapters::OpenSearch::IndicesAPI, @adapter.indices
  end

  def test_indices_api_methods
    assert_respond_to @adapter.indices, :get
    assert_respond_to @adapter.indices, :stats
    assert_respond_to @adapter.indices, :refresh
  end
end
