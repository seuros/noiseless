# frozen_string_literal: true

Vial.configure do |config|
  # Use gem's test directories, not dummy app's
  gem_root = Rails.root.join("../..")
  config.source_paths = [gem_root.join("test/vials")]
  config.output_path = gem_root.join("test/fixtures")
end
