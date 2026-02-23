# frozen_string_literal: true

module Noiseless
  class MappingDefinitionProcessor
    def self.process(mapping_block)
      return {} unless mapping_block

      processor = new
      processor.instance_eval(&mapping_block)
      processor.to_index_config
    end

    def initialize
      @settings = {}
      @properties = {}
    end

    def settings(&)
      settings_builder = SettingsBuilder.new
      settings_builder.instance_eval(&)
      @settings = settings_builder.to_hash
    end

    def properties(&)
      properties_builder = PropertiesBuilder.new
      properties_builder.instance_eval(&)
      @properties = properties_builder.to_hash
    end

    # Delegate to settings builder for nested methods
    def analysis(&)
      settings { analysis(&) }
    end

    def to_index_config
      config = {}
      config[:settings] = @settings unless @settings.empty?
      config[:mappings] = { properties: @properties } unless @properties.empty?
      config
    end

    class SettingsBuilder
      def initialize
        @settings = {}
      end

      def index(&)
        index_builder = IndexSettingsBuilder.new
        index_builder.instance_eval(&)
        @settings[:index] = index_builder.to_hash
      end

      def analysis(&)
        analysis_builder = AnalysisBuilder.new
        analysis_builder.instance_eval(&)
        @settings[:analysis] = analysis_builder.to_hash
      end

      def to_hash
        @settings
      end
    end

    class IndexSettingsBuilder
      def initialize
        @index_settings = {}
      end

      def analysis(&)
        analysis_builder = AnalysisBuilder.new
        analysis_builder.instance_eval(&)
        @index_settings[:analysis] = analysis_builder.to_hash
      end

      def to_hash
        @index_settings
      end
    end

    class AnalysisBuilder
      def initialize
        @analysis = {}
      end

      def normalizer(name = nil, &)
        @analysis[:normalizer] ||= {}
        if name && block_given?
          # Define a specific normalizer
          normalizer_builder = NormalizerBuilder.new
          normalizer_builder.instance_eval(&)
          @analysis[:normalizer][name] = normalizer_builder.to_hash
        elsif block_given?
          # Handle nested normalizer definitions
          normalizer_definitions = NormalizerDefinitions.new
          normalizer_definitions.instance_eval(&)
          @analysis[:normalizer].merge!(normalizer_definitions.to_hash)
        end
      end

      def analyzer(name = nil, &)
        @analysis[:analyzer] ||= {}
        if name && block_given?
          # Define a specific analyzer
          analyzer_builder = AnalyzerBuilder.new
          analyzer_builder.instance_eval(&)
          @analysis[:analyzer][name] = analyzer_builder.to_hash
        elsif block_given?
          # Handle nested analyzer definitions
          analyzer_definitions = AnalyzerDefinitions.new
          analyzer_definitions.instance_eval(&)
          @analysis[:analyzer].merge!(analyzer_definitions.to_hash)
        end
      end

      def to_hash
        @analysis
      end
    end

    class NormalizerBuilder
      def initialize
        @config = {}
      end

      def type(value)
        @config[:type] = value
      end

      def char_filter(filters)
        @config[:char_filter] = filters
      end

      def filter(filters)
        @config[:filter] = filters
      end

      def to_hash
        @config
      end
    end

    class AnalyzerDefinitions
      def initialize
        @analyzers = {}
      end

      def method_missing(name, &)
        if block_given?
          analyzer_builder = AnalyzerBuilder.new
          analyzer_builder.instance_eval(&)
          @analyzers[name] = analyzer_builder.to_hash
        else
          super
        end
      end

      def respond_to_missing?(_name, _include_private = false)
        true
      end

      def to_hash
        @analyzers
      end
    end

    class NormalizerDefinitions
      def initialize
        @normalizers = {}
      end

      def method_missing(name, &)
        if block_given?
          normalizer_builder = NormalizerBuilder.new
          normalizer_builder.instance_eval(&)
          @normalizers[name] = normalizer_builder.to_hash
        else
          super
        end
      end

      def respond_to_missing?(_name, _include_private = false)
        true
      end

      def to_hash
        @normalizers
      end
    end

    class AnalyzerBuilder
      def initialize
        @config = {}
      end

      def type(value)
        @config[:type] = value
      end

      def stopwords(value)
        @config[:stopwords] = value
      end

      def filter(filters)
        @config[:filter] = filters
      end

      def to_hash
        @config
      end
    end

    class PropertiesBuilder
      def initialize
        @properties = {}
      end

      # Define a property with a symbol name and type
      def method_missing(name, type_or_field, options = {})
        @properties[name] = { type: type_or_field }.merge(options)
      end

      def respond_to_missing?(_name, _include_private = false)
        true
      end

      def to_hash
        @properties
      end
    end
  end
end
