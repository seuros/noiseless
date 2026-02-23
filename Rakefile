# frozen_string_literal: true

require "bundler/setup"

# Only load gem tasks when running from gem root
require "bundler/gem_tasks" if File.exist?("noiseless.gemspec")

require "rake/testtask"

# Load rake tasks from lib/tasks
Dir.glob("lib/tasks/*.rake").each { |r| load r }

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test
