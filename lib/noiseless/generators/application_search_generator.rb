# frozen_string_literal: true

require "rails/generators"

module Noiseless
  module Generators
    class ApplicationSearchGenerator < Rails::Generators::Base
      desc "Generate ApplicationSearch class for your application"

      source_root File.expand_path("templates", __dir__)

      def create_application_search
        create_file "app/search/application_search.rb", <<~RUBY
          # frozen_string_literal: true

          # Base class for all search models
          class ApplicationSearch < Noiseless::Model
            # Inherits static and dynamic search methods using default_connection
          end
        RUBY
      end
    end
  end
end
