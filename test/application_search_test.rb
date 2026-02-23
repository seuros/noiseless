# frozen_string_literal: true

require "test_helper"
require "application_search"

class ApplicationSearchTest < ActiveSupport::TestCase
  test "ApplicationSearch is abstract" do
    assert_predicate ApplicationSearch, :abstract?
  end

  test "can create concrete search models" do
    # Create a concrete search class
    product_search_class = Class.new(ApplicationSearch) do
      def self.name
        "Product::Search"
      end
    end

    assert_not product_search_class.abstract?
  end

  test "abstract class provides base functionality" do
    # Verify ApplicationSearch has the expected methods
    assert_respond_to ApplicationSearch, :search
    assert_respond_to ApplicationSearch, :search_index
    assert_respond_to ApplicationSearch, :connection
  end
end
