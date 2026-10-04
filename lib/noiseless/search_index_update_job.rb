# frozen_string_literal: true

module Noiseless
  class SearchIndexUpdateJob
    def self.perform_later(model_class_name, record_id, operation, options = {})
      if defined?(ActiveJob::Base)
        ActiveJobSearchIndexUpdateJob.perform_later(model_class_name, record_id, operation, options)
      elsif defined?(Sidekiq)
        SidekiqSearchIndexUpdateJob.perform_async(model_class_name, record_id, operation, options)
      else
        # Fallback to immediate execution
        perform_now(model_class_name, record_id, operation, options)
      end
    end

    def self.perform_now(model_class_name, record_id, operation, options = {})
      model_class = model_class_name.constantize

      case operation
      when "update"
        record = model_class.find(record_id)
        record.document_manager.update_document(**options)
      when "delete"
        # For delete operations, we need to construct a minimal object
        # since the record might already be deleted from the database
        document_manager = DocumentManager.new(
          DeletedRecord.new(model_class, record_id)
        )
        document_manager.delete_document(**options)
      else
        raise ArgumentError, "Unknown operation: #{operation}"
      end
    rescue StandardError => e
      raise if options[:raise_on_error]

      Rails.logger&.error "Noiseless: Background job failed for #{model_class_name}##{record_id}: #{e.message}"
    end

    # Minimal object for deleted records
    class DeletedRecord
      def initialize(model_class, record_id)
        @model_class = model_class
        @record_id = record_id
      end

      def id
        @record_id
      end

      def class
        @model_class
      end

      def to_search_document
        nil
      end
    end

    # Queued runs raise so the job backend retries instead of recording success.
    module Queued
      def perform(model_class_name, record_id, operation, options = {})
        SearchIndexUpdateJob.perform_now(model_class_name, record_id, operation, options.merge(raise_on_error: true))
      end
    end
  end

  # ActiveJob integration
  if defined?(ActiveJob::Base)
    class ActiveJobSearchIndexUpdateJob < ActiveJob::Base
      include SearchIndexUpdateJob::Queued

      queue_as :default
    end
  end

  # Sidekiq integration
  if defined?(Sidekiq)
    class SidekiqSearchIndexUpdateJob
      include Sidekiq::Worker
      include SearchIndexUpdateJob::Queued
    end
  end
end
