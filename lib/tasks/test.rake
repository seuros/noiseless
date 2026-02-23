# frozen_string_literal: true

namespace :test do
  desc "Prepare test database"
  task :prepare do
    require_relative "../../test/dummy/config/environment"
    ActiveRecord::Tasks::DatabaseTasks.create_current("test")
    ActiveRecord::Base.establish_connection(:test)
    ActiveRecord::Migration.maintain_test_schema!
  end
end
