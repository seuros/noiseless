# frozen_string_literal: true

require_relative "lib/noiseless/version"

Gem::Specification.new do |spec|
  spec.name          = "noiseless"
  spec.version       = Noiseless::VERSION
  spec.authors     = ["Abdelkader Boudih"]
  spec.email       = ["terminale@gmail.com"]

  spec.summary       = "Async-first Rails search abstraction with multi-backend support"
  spec.description   = "Noiseless is a Rails-focused, ActiveRecord-style search abstraction supporting Elasticsearch, OpenSearch, Typesense, and PostgreSQL with asynchronous querying and a chainable DSL."
  spec.homepage      = "https://github.com/seuros/noiseless"
  spec.license       = "BSD-3-Clause"

  spec.required_ruby_version = ">= 3.4"

  spec.files         = Dir["lib/**/*", "README.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", "~> 8.1"
  spec.add_dependency "async", "~> 2.20"
  spec.add_dependency "async-http", "~> 0.80"
  spec.add_dependency "async-pool", "~> 0.8"
  spec.add_dependency "railties", "~> 8.1"
  spec.add_dependency "zeitwerk", "~> 2.7"
  # rubocop:disable Gemspec/DevelopmentDependencies
  spec.add_development_dependency "async-safe", "~> 0.5"
  spec.add_development_dependency "minitest", "~> 5.27"
  spec.add_development_dependency "sqlite3", "~> 2.9"
  spec.add_development_dependency "vcr", "~> 6.4"
  spec.add_development_dependency "webmock", "~> 3.26"
  # Performance benchmarking dependencies (optional)
  spec.add_development_dependency "sus", "~> 0.35"
  spec.add_development_dependency "sus-fixtures-benchmark", "~> 0.2"
  # rubocop:enable Gemspec/DevelopmentDependencies
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = "https://github.com/seuros/noiseless"
end
