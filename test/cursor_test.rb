# frozen_string_literal: true

require "test_helper"

class CursorTest < ActiveSupport::TestCase
  test "cursor round-trips and rejects garbage" do
    cursor = Noiseless::Pagination::Cursor.new(field: :id, value: 42, direction: :desc)
    decoded = Noiseless::Pagination::Cursor.decode(cursor.encode)

    assert_equal ["id", 42, :desc], [decoded.field, decoded.value, decoded.direction]
    assert_nil Noiseless::Pagination::Cursor.decode("not!base64")
  end
end
