# frozen_string_literal: true

module Noiseless
  module RecordClassResolver
    # Search definitions and database models are different kinds of classes.
    # Only a Noiseless::Model uses the explicit record_class mapping.
    def self.resolve(model_class)
      if model_class.is_a?(Class) && model_class <= Model
        model_class.record_class
      else
        model_class
      end
    end
  end
end
