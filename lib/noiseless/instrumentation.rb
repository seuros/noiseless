# frozen_string_literal: true

module Noiseless
  # Instrumentation via ActiveSupport
  module Instrumentation
    def instrument(event, payload = {})
      start_time = Time.current
      payload = payload.merge(
        adapter: self.class.name,
        connection: connection_info,
        start_time: start_time
      )

      result = ActiveSupport::Notifications.instrument("noiseless.#{event}", payload) do
        yield if block_given?
      end

      # Update runtime tracking for Rails
      add_to_runtime(Time.current - start_time) if defined?(Rails) && Rails.respond_to?(:application) && Rails.application

      result
    end

    private

    def connection_info
      {
        hosts: @hosts&.take(3), # Limit to first 3 hosts for brevity
        adapter_class: self.class.name
      }
    rescue StandardError
      { adapter_class: self.class.name }
    end

    def add_to_runtime(duration)
      state = ActiveSupport::IsolatedExecutionState
      state[:noiseless_runtime] = (state[:noiseless_runtime] || 0) + (duration * 1000)
    end
  end
end
