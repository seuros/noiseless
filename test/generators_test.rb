# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"

class GeneratorsTest < Rails::Generators::TestCase
  tests Noiseless::Generators::ApplicationSearchGenerator
  destination Rails.root.join("tmp/generators")

  setup do
    prepare_destination
  end

  test "generates application search file" do
    run_generator

    assert_file "app/search/application_search.rb" do |content|
      assert_match(/class ApplicationSearch < Noiseless::Model/, content)
      assert_match(/frozen_string_literal: true/, content)
    end
  end
end
