# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in action_mcp.gemspec.
gemspec

gem "rubocop", require: false

# Support testing against Rails edge/development branch
if ENV["RAILS_VERSION"] == "dev"
  gem "activesupport", github: "rails/rails", branch: "main"
  gem "railties", github: "rails/rails", branch: "main"
else
  gem "activesupport", ENV.fetch("RAILS_VERSION", "~> 8.1.0")
  gem "railties", ENV.fetch("RAILS_VERSION", "~> 8.1.0")
end

# Start debugger with binding.b [https://github.com/ruby/debug]
gem "debug", ">= 1.0.0"

gem "pg"
# Pagination gems kept only for benchmarking comparison
gem "benchmark"
gem "benchmark-ips"
gem "kaminari", require: false
gem "pagy", require: false

gem "listen", group: :development
gem "simplecov", "~> 0.22.0"

# Mermaid diagram generation
gem "diagram"
gem "mermaid"

# Vial for fixture management
gem "faker", group: %i[development test]
gem "vial", group: %i[development test]
