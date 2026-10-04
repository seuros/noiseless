# frozen_string_literal: true

require_relative "execution_modules/opensearch_execution"

module Noiseless
  module Adapters
    class OpenSearch < Adapter
      include ExecutionModules::OpensearchExecution

      ClusterAPI = Adapters::ClusterAPI
      IndicesAPI = Adapters::IndicesAPI

      def point_in_time_search(ast_node, pit_id:, **)
        query_hash = ast_to_hash(ast_node)
        Async do
          execute_point_in_time_search(query_hash, pit_id: pit_id, **)
        end
      end

      def search_template(template_id:, params: {}, **)
        Async do
          execute_search_template(template_id: template_id, params: params, **)
        end
      end

      def cluster
        @cluster ||= ClusterAPI.new(self)
      end

      def indices
        @indices ||= IndicesAPI.new(self)
      end

      def pipelines
        @pipelines ||= PipelinesAPI.new(self)
      end

      def rules
        @rules ||= RulesAPI.new(self)
      end

      def workload_groups
        @workload_groups ||= WorkloadGroupsAPI.new(self)
      end

      def search_raw(query_body, indexes: [], **)
        Async do
          execute_search(query_body, indexes: indexes, **)
        end
      end

      class PipelinesAPI
        def initialize(adapter)
          @adapter = adapter
        end

        def create(name, request_processors: nil, response_processors: nil, phase_results_processors: nil, description: nil)
          Sync do
            @adapter.send(:execute_create_pipeline, name, request_processors:, response_processors:,
                                                          phase_results_processors:, description:)
          end
        end

        alias put create

        def get(name) = Sync { @adapter.send(:execute_get_pipeline, name) }
        def list = Sync { @adapter.send(:execute_list_pipelines) }
        def delete(name) = Sync { @adapter.send(:execute_delete_pipeline, name) }
        def exists?(name) = Sync { @adapter.send(:execute_pipeline_exists?, name) }

        alias all list
      end

      # Rule-based auto-tagging; needs the workload-management plugin.
      class RulesAPI
        def initialize(adapter)
          @adapter = adapter
        end

        def create(feature_type, description:, value:, **attributes)
          Sync { @adapter.send(:execute_create_rule, feature_type, description:, value:, **attributes) }
        end

        def update(feature_type, id, **changes) = Sync { @adapter.send(:execute_update_rule, feature_type, id, **changes) }
        def get(feature_type, id) = Sync { @adapter.send(:execute_get_rule, feature_type, id) }

        def list(feature_type, search_after: nil)
          Sync { @adapter.send(:execute_list_rules, feature_type, search_after:) }
        end

        def delete(feature_type, id) = Sync { @adapter.send(:execute_delete_rule, feature_type, id) }
        def exists?(feature_type, id) = Sync { @adapter.send(:execute_rule_exists?, feature_type, id) }

        alias all list
      end

      # Workload groups that workload_group rules point at; needs the workload-management plugin.
      class WorkloadGroupsAPI
        def initialize(adapter)
          @adapter = adapter
        end

        def create(name, resource_limits:, resiliency_mode: "soft")
          Sync { @adapter.send(:execute_create_workload_group, name, resource_limits:, resiliency_mode:) }
        end

        def get(name) = Sync { @adapter.send(:execute_get_workload_group, name) }
        def delete(name) = Sync { @adapter.send(:execute_delete_workload_group, name) }
      end

      private

      def default_port
        ENV["OPENSEARCH_PORT"] || 9200
      end
    end
  end
end
