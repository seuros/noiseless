# frozen_string_literal: true

# Configure Faker for deterministic generation
Faker::Config.random = Random.new(Vial.config.seed)

vial :articles, id_base: 1_000_000, id_range: 900_000 do
  base do
    status "published"
  end

  sequence(:title) { |i| "#{Faker::Hacker.verb.titleize} #{Faker::Hacker.adjective.titleize} #{Faker::Hacker.noun.titleize} - Part #{i}" }
  sequence(:content) { |_i| Faker::Lorem.paragraphs(number: 3).join("\n\n") }
  sequence(:author) { |i| "Author_#{(i % 50).to_s.rjust(3, '0')}" }
  sequence(:category) { |i| %w[technology programming development science business][i % 5] }
  sequence(:tags) { |_i| Faker::Lorem.words(number: rand(2..5)) }
  sequence(:published_at) { |i| (365 - (i % 365)).days.ago }
  sequence(:view_count) { |i| [0, 5000 - (i % 5000) + Random.new(i).rand(-500..500)].max }

  variant :published do
    title sequence(:title)
    content sequence(:content)
    author sequence(:author)
    category sequence(:category)
    status "published"
    tags sequence(:tags)
    published_at sequence(:published_at)
    view_count sequence(:view_count)
  end

  variant :draft do
    title sequence(:title)
    content sequence(:content)
    author sequence(:author)
    category sequence(:category)
    status "draft"
    tags sequence(:tags)
    published_at nil
    view_count 0
  end

  # Generate 9k published + 1k draft = 10k total
  generate 9000, :published
  generate 1000, :draft
end
