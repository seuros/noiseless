#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "benchmark/ips"
require "active_record"
require "kaminari"

# Add pagy if available
begin
  require "pagy"
  PAGY_AVAILABLE = true
rescue LoadError
  PAGY_AVAILABLE = false
  puts "Pagy not installed - run: gem install pagy"
end

# Setup in-memory SQLite for benchmarking
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

ActiveRecord::Schema.define do
  create_table :items, force: true do |t|
    t.string :name
    t.string :category
    t.integer :position
    t.timestamps
  end

  add_index :items, :position
  add_index :items, :id
end

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class Item < ApplicationRecord
end

# Seed data
record_count = ENV.fetch("BENCHMARK_RECORDS", 10_000).to_i
puts "Seeding #{record_count} records..."
ActiveRecord::Base.transaction do
  record_count.times do |i|
    Item.create!(name: "Item #{i}", category: "cat_#{i % 100}", position: i)
  end
end
puts "Done seeding."

# Pagination implementations
module PaginationMethods
  # Raw LIMIT/OFFSET
  def self.raw_offset(page, per_page)
    offset = (page - 1) * per_page
    Item.order(:id).limit(per_page).offset(offset).to_a
  end

  # Kaminari
  def self.kaminari(page, per_page)
    Item.order(:id).page(page).per(per_page).to_a
  end

  # Pagy (if available) - v43+ API
  if PAGY_AVAILABLE
    def self.pagy_paginate(page, per_page)
      count = Item.count
      pagy = Pagy::Offset.new(count:, page:, limit: per_page)
      records = Item.order(:id).offset(pagy.offset).limit(pagy.limit).to_a
      [pagy, records]
    end

    def self.pagy_countless(page, per_page)
      # Skips COUNT query - faster for large datasets
      records = Item.order(:id).offset((page - 1) * per_page).limit(per_page + 1).to_a
      has_more = records.size > per_page
      records = records.first(per_page)
      [has_more, records]
    end
  end

  # Keyset pagination (cursor-based) - O(1)
  def self.keyset(last_id, per_page)
    scope = Item.order(:id).limit(per_page)
    scope = scope.where("id > ?", last_id) if last_id
    scope.to_a
  end

  # Keyset with position (for custom sorting)
  def self.keyset_position(last_position, per_page)
    scope = Item.order(:position).limit(per_page)
    scope = scope.where("position > ?", last_position) if last_position
    scope.to_a
  end
end

puts "\n#{'=' * 60}"
puts "PAGINATION BENCHMARK - 100,000 records"
puts "=" * 60

# Test different page depths
[1, 100, 1000, 5000].each do |page|
  per_page = 20

  puts "\n--- Page #{page} (offset: #{(page - 1) * per_page}) ---\n\n"

  Benchmark.ips do |x|
    x.config(time: 3, warmup: 1)

    x.report("Raw OFFSET") do
      PaginationMethods.raw_offset(page, per_page)
    end

    x.report("Kaminari") do
      PaginationMethods.kaminari(page, per_page)
    end

    if PAGY_AVAILABLE
      x.report("Pagy") do
        PaginationMethods.pagy_paginate(page, per_page)
      end

      x.report("Pagy Countless") do
        PaginationMethods.pagy_countless(page, per_page)
      end
    end

    # Keyset uses last_id, simulate by calculating
    last_id = (page - 1) * per_page
    x.report("Keyset (cursor)") do
      PaginationMethods.keyset(last_id, per_page)
    end

    x.compare!
  end
end

puts "\n#{'=' * 60}"
puts "MEMORY BENCHMARK"
puts "=" * 60

require "objspace"

def measure_memory
  GC.start
  GC.start
  before = ObjectSpace.memsize_of_all
  yield
  GC.start
  after = ObjectSpace.memsize_of_all
  after - before
end

page = 1000
per_page = 20

puts "\nMemory usage at page #{page}:\n\n"

memory_results = {}

memory_results["Raw OFFSET"] = measure_memory { PaginationMethods.raw_offset(page, per_page) }
memory_results["Kaminari"] = measure_memory { PaginationMethods.kaminari(page, per_page) }

if PAGY_AVAILABLE
  memory_results["Pagy"] = measure_memory { PaginationMethods.pagy_paginate(page, per_page) }
  memory_results["Pagy Countless"] = measure_memory { PaginationMethods.pagy_countless(page, per_page) }
end

last_id = (page - 1) * per_page
memory_results["Keyset"] = measure_memory { PaginationMethods.keyset(last_id, per_page) }

memory_results.sort_by { |_, v| v }.each do |name, bytes|
  puts "#{name.ljust(20)} #{(bytes / 1024.0).round(2)} KB"
end

puts "\n#{'=' * 60}"
puts "CONCLUSION"
puts "=" * 60
puts <<~CONCLUSION

  For API-based search (noiseless):

  1. KEYSET PAGINATION - Best for:
     - "Load more" / infinite scroll
     - Large datasets
     - Consistent O(1) performance

  2. RAW LIMIT/OFFSET - Best for:
     - Simple implementation
     - Small-medium datasets
     - When page jumping is needed

  3. PAGY COUNTLESS - Best for:
     - When total count is expensive
     - "Has more" pattern

  Recommendation: Remove Kaminari, use raw LIMIT/OFFSET
  with optional keyset support for large datasets.

CONCLUSION
