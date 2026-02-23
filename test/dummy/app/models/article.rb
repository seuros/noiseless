# frozen_string_literal: true

class Article < ApplicationRecord
  self.table_name = "articles"

  # SearchFiction provides the search functionality
  class SearchFiction < Noiseless::Model
    def self.name
      "Article::SearchFiction"
    end

    def self.search_index
      ["articles"]
    end

    def self.connection(name = nil)
      @connection_name = name if name
      @connection_name || :primary
    end
  end

  def to_search_hash
    {
      id: id,
      title: title,
      content: content,
      author: author,
      status: status,
      tags: tags,
      published_at: published_at,
      view_count: view_count,
      category: category
    }
  end
end
