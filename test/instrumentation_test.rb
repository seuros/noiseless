# frozen_string_literal: true

require "test_helper"

class InstrumentationTest < ActiveSupport::TestCase
  test "instruments events with ActiveSupport::Notifications" do
    instrumented_class = Class.new do
      include Noiseless::Instrumentation
    end

    events = []
    ActiveSupport::Notifications.subscribe("noiseless.test") do |name, _start, _finish, _id, payload|
      events << { name: name, payload: payload }
    end

    instance = instrumented_class.new
    result = instance.instrument(:test, { key: "value" }) do
      "test_result"
    end

    assert_equal "test_result", result
    assert_equal 1, events.size
    assert_equal "noiseless.test", events.first[:name]
    assert_includes events.first[:payload], :key
    assert_equal "value", events.first[:payload][:key]
  ensure
    ActiveSupport::Notifications.unsubscribe("noiseless.test")
  end

  test "runtime recorded inside an Async task is visible to the caller" do
    instance = Class.new { include Noiseless::Instrumentation }.new
    ActiveSupport::IsolatedExecutionState[:noiseless_runtime] = 0

    Sync { Async { instance.instrument(:test) { sleep 0.01 } }.wait }

    assert_operator ActiveSupport::IsolatedExecutionState[:noiseless_runtime], :>, 0
  ensure
    ActiveSupport::IsolatedExecutionState[:noiseless_runtime] = nil
  end
end
