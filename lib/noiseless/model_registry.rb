# frozen_string_literal: true

module Noiseless
  class ModelRegistry
    include Singleton

    def initialize
      @models = {}
      @models_by_index = {}
    end

    def register(model_class, options = {})
      model_name = model_class.name.to_sym
      @models[model_name] = {
        class: model_class,
        options: options
      }

      # Index models by their search index names
      index_names = Array(model_class.search_index || default_index_name(model_class))
      index_names.each do |index_name|
        @models_by_index[index_name.to_sym] ||= []
        @models_by_index[index_name.to_sym] << model_class
      end
    end

    def unregister(model_class)
      model_name = model_class.name.to_sym
      @models.delete(model_name)

      # Remove from index mapping
      @models_by_index.each do |index_name, models|
        models.delete(model_class)
        @models_by_index.delete(index_name) if models.empty?
      end
    end

    def all_models
      @models.values.map { |entry| entry[:class] }
    end

    def find_model(name_or_class)
      case name_or_class
      when String, Symbol
        entry = @models[name_or_class.to_sym]
        entry ? entry[:class] : nil
      when Class
        @models.find { |_, entry| entry[:class] == name_or_class }&.last&.fetch(:class)
      end
    end

    def models_for_index(index_name)
      @models_by_index[index_name.to_sym] || []
    end

    def all_indexes
      @models_by_index.keys.map(&:to_s)
    end

    def searchable_models
      @models.reject { |_, entry| entry[:options][:searchable] == false }
             .values
             .map { |entry| entry[:class] }
    end

    def clear!
      @models.clear
      @models_by_index.clear
    end

    private

    def default_index_name(model_class)
      model_class.name.demodulize.underscore.pluralize
    end
  end
end
