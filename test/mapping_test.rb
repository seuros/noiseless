# frozen_string_literal: true

require "test_helper"

class MappingTest < ActiveSupport::TestCase
  test "converts document to hash" do
    doc = { title: "Test", content: "Content" }
    mapping = Noiseless::Mapping.new(doc)
    assert_equal doc, mapping.to_h
  end

  test "deserializes hits" do
    hit = { "_source" => { "title" => "Test" } }
    result = Noiseless::Mapping.deserialize(hit)
    assert_equal({ "title" => "Test" }, result)
  end
end
