# frozen_string_literal: true

# Test id_base and id_range
vial :custom_id_articles, id_base: 100_000, id_range: 10_000 do
  base do
    title "Custom ID Article"
    content "Testing custom ID ranges"
    author "Test Author"
    status "published"
    category "test"
    tags %w[test custom-id]
    published_at 1.day.ago
    view_count 0
  end

  generate 2
end
