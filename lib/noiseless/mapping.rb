# frozen_string_literal: true

module Noiseless
  class Mapping
    class << self
      def inherited(subclass)
        super
        # Inherit mappings and settings from parent class
        subclass.instance_variable_set(:@mapping_definition, @mapping_definition&.dup)
        subclass.instance_variable_set(:@index_settings, @index_settings&.dup)
        subclass.instance_variable_set(:@analyzers, @analyzers&.dup)
      end

      def mapping(&)
        if block_given?
          @mapping_definition = MappingDefinition.new
          @mapping_definition.instance_eval(&)
        end
        @mapping_definition
      end

      def settings(settings_hash = nil, &)
        if settings_hash
          @index_settings = (@index_settings || {}).merge(settings_hash)
        elsif block_given?
          @index_settings ||= {}
          builder = SettingsBuilder.new(@index_settings)
          builder.instance_eval(&)
        end
        @index_settings
      end

      def analyzer(name, definition)
        @analyzers ||= {}
        @analyzers[name.to_s] = definition
      end

      def analyzers
        @analyzers || {}
      end

      def index_name(name = nil)
        @index_name = name.to_s if name
        @index_name
      end

      def to_mapping_hash
        return {} unless @mapping_definition

        { properties: @mapping_definition.to_hash }
      end

      def to_settings_hash
        settings = @index_settings || {}

        # Add analyzers to settings if any are defined
        if @analyzers&.any?
          settings = settings.deep_merge(
            analysis: {
              analyzer: @analyzers
            }
          )
        end

        settings
      end

      def load_settings_from_file(file_path)
        return unless File.exist?(file_path)

        content = File.read(file_path)
        parsed_settings = case File.extname(file_path)
                          when ".json"
                            JSON.parse(content)
                          when ".yml", ".yaml"
                            YAML.load(content)
                          else
                            raise ArgumentError, "Unsupported file format: #{File.extname(file_path)}"
                          end

        settings(parsed_settings)
      end
    end

    # Instance methods
    def initialize(document)
      @document = document
    end

    def to_h
      if @document.respond_to?(:to_search_document)
        @document.to_search_document
      elsif @document.respond_to?(:to_h)
        @document.to_h
      elsif @document.respond_to?(:attributes)
        @document.attributes
      else
        @document
      end
    end

    def self.deserialize(hit)
      hit["_source"]
    end
  end

  # DSL for building mapping definitions
  class MappingDefinition
    def initialize
      @properties = {}
    end

    def field(name, type, **options)
      @properties[name.to_s] = { type: type.to_s }.merge(options)
    end

    def keyword(name, **)
      field(name, :keyword, **)
    end

    def text(name, **)
      field(name, :text, **)
    end

    def integer(name, **)
      field(name, :integer, **)
    end

    def long(name, **)
      field(name, :long, **)
    end

    def float(name, **)
      field(name, :float, **)
    end

    def double(name, **)
      field(name, :double, **)
    end

    def boolean(name, **)
      field(name, :boolean, **)
    end

    def date(name, **)
      field(name, :date, **)
    end

    def geo_point(name, **)
      field(name, :geo_point, **)
    end

    def object(name, **, &)
      if block_given?
        nested_mapping = MappingDefinition.new
        nested_mapping.instance_eval(&)
        field(name, :object, properties: nested_mapping.to_hash, **)
      else
        field(name, :object, **)
      end
    end

    def nested(name, **, &)
      if block_given?
        nested_mapping = MappingDefinition.new
        nested_mapping.instance_eval(&)
        field(name, :nested, properties: nested_mapping.to_hash, **)
      else
        field(name, :nested, **)
      end
    end

    def to_hash
      @properties
    end
  end

  # DSL for building settings
  class SettingsBuilder
    def initialize(settings_hash)
      @settings = settings_hash
    end

    def number_of_shards(count)
      @settings[:number_of_shards] = count
    end

    def number_of_replicas(count)
      @settings[:number_of_replicas] = count
    end

    def refresh_interval(interval)
      @settings[:refresh_interval] = interval
    end

    def max_result_window(size)
      @settings[:max_result_window] = size
    end

    def analysis(&)
      @settings[:analysis] ||= {}
      builder = AnalysisBuilder.new(@settings[:analysis])
      builder.instance_eval(&)
    end
  end

  # DSL for analysis settings
  class AnalysisBuilder
    def initialize(analysis_hash)
      @analysis = analysis_hash
    end

    def analyzer(name, &)
      @analysis[:analyzer] ||= {}
      builder = AnalyzerBuilder.new
      builder.instance_eval(&)
      @analysis[:analyzer][name.to_s] = builder.to_hash
    end

    def tokenizer(name, definition)
      @analysis[:tokenizer] ||= {}
      @analysis[:tokenizer][name.to_s] = definition
    end

    def filter(name, definition)
      @analysis[:filter] ||= {}
      @analysis[:filter][name.to_s] = definition
    end
  end

  # DSL for analyzer definition
  class AnalyzerBuilder
    def initialize
      @definition = {}
    end

    def tokenizer(name)
      @definition[:tokenizer] = name.to_s
    end

    def filter(*names)
      @definition[:filter] = names.map(&:to_s)
    end

    def char_filter(*names)
      @definition[:char_filter] = names.map(&:to_s)
    end

    def to_hash
      @definition
    end
  end
end
