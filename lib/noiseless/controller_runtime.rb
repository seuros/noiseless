# frozen_string_literal: true

module Noiseless
  # Runtime tracking for Rails
  module ControllerRuntime
    extend ActiveSupport::Concern

    protected

    def append_info_to_payload(payload)
      super
      payload[:noiseless_runtime] = noiseless_runtime
    end

    def cleanup_view_runtime
      runtime_before_render = noiseless_runtime
      runtime = super
      runtime_after_render = noiseless_runtime
      runtime + runtime_after_render - runtime_before_render
    end

    private

    def noiseless_runtime
      ActiveSupport::IsolatedExecutionState[:noiseless_runtime] ||= 0
    end

    module ClassMethods
      def log_process_action(payload)
        messages = super
        runtime = payload[:noiseless_runtime]
        messages << ("Noiseless: %.1fms" % runtime) if runtime&.positive?
        messages
      end
    end
  end
end
