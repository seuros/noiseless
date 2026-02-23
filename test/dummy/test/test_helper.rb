# frozen_string_literal: true

require "async/safe"
Async::Safe.enable!

require "simplecov"
SimpleCov.start

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require_relative "../config/environment"
require "rails/test_help"
require "minitest/autorun"
require "minitest/spec"

# Load the gem
require "noiseless"

# Manually require test helper since it's ignored by Zeitwerk
require "noiseless/test_helper"

module ActiveSupport
  class TestCase
    # Include Noiseless::TestHelper for all tests
    include Noiseless::TestHelper

    # Set fixture path to gem's test/fixtures directory
    self.fixture_paths = [File.expand_path("../../fixtures", __dir__)]
  end
end
