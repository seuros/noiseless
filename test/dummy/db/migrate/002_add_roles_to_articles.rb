# frozen_string_literal: true

class AddRolesToArticles < ActiveRecord::Migration[8.0]
  def change
    add_column :articles, :roles, :string, array: true, default: []
  end
end
