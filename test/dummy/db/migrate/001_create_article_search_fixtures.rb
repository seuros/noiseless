# frozen_string_literal: true

class CreateArticleSearchFixtures < ActiveRecord::Migration[8.0]
  def change
    # Enable PostgreSQL extensions for full-text search
    enable_extension "pg_trgm"
    enable_extension "unaccent"
    enable_extension "fuzzystrmatch"

    create_table :articles do |t|
      t.string :title, null: false
      t.text :content, null: false
      t.string :author, null: false
      t.string :status, default: "draft"
      t.json :tags, default: []
      t.datetime :published_at
      t.integer :view_count, default: 0
      t.string :category

      t.timestamps
    end

    add_index :articles, :title
    add_index :articles, :status
    add_index :articles, :category
    add_index :articles, :published_at
  end
end
