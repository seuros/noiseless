# frozen_string_literal: true

require "rails/railtie"
require_relative "instrumentation"
require_relative "runtime_reset_middleware"

module Noiseless
  class Railtie < Rails::Railtie
    railtie_name :noiseless

    config.noiseless = ActiveSupport::OrderedOptions.new

    initializer "noiseless.configure" do |_app|
      # Load configuration from config/noiseless.yml
      Noiseless.load_configuration!
    end

    initializer "noiseless.instrumentation" do |app|
      # Attach log subscriber
      Noiseless::LogSubscriber.attach_to :noiseless

      # Include controller runtime tracking in ActionController
      ActiveSupport.on_load(:action_controller) do
        include Noiseless::ControllerRuntime
      end

      # Reset runtime tracking at the beginning of each request
      app.middleware.use Noiseless::RuntimeResetMiddleware
    end

    generators do
      require_relative "generators/application_search_generator"
    end
  end
end
