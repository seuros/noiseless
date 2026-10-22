# frozen_string_literal: true

# Unit tests need neither the Rails dummy app nor a running database.
require "async/safe"
Async::Safe.enable!

require "minitest/autorun"
require "minitest/mock"
require "noiseless"
require_relative "support/search_contract_case"
