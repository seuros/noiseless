# frozen_string_literal: true

module Noiseless
  class RuntimeResetMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      # Reset runtime tracking at the beginning of each request
      Thread.current[:noiseless_runtime] = 0
      @app.call(env)
    end
  end
end
