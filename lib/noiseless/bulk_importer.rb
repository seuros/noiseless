# frozen_string_literal: true

module Noiseless
  class BulkImporter
    attr_reader :model_class, :errors

    def initialize(model_class, connection: nil)
      @model_class = model_class
      @connection = connection || model_class.connection
      @errors = []
    end

    def import(relation_or_records = nil,
               batch_size: 1000,
               transform: nil,
               preprocess: nil,
               force: false,
               refresh: true,
               **)
      @errors.clear

      # Create index if force is true
      if force
        delete_index
        create_index
      end

      # Get records to import
      records = resolve_records(relation_or_records)

      total_imported = 0

      records.each_slice(batch_size) do |batch|
        # Apply preprocessing to the entire batch
        processed_batch = preprocess ? preprocess.call(batch) : batch

        # Transform individual records and build actions
        actions = build_bulk_actions(processed_batch, transform)

        # Execute bulk operation
        begin
          client = Noiseless.connections.client(@connection)
          response = client.bulk(actions, refresh: refresh, **)

          # Check for errors in response
          collect_errors(response, processed_batch)

          total_imported += actions.size
        rescue StandardError => e
          @errors << {
            error: e.message,
            batch: processed_batch.map { |r| identify_record(r) }
          }
        end
      end

      {
        imported: total_imported,
        errors: @errors.size,
        error_details: @errors
      }
    end

    def import_scoped(scope, **)
      import(scope, **)
    end

    def reindex(batch_size: 1000, **)
      raise ArgumentError, "Model class #{model_class} must respond to :all for reindexing" unless model_class.respond_to?(:all)

      import(model_class.all, batch_size: batch_size, force: true, **)
    end

    private

    def resolve_records(relation_or_records)
      case relation_or_records
      when nil
        model_class.respond_to?(:all) ? model_class.all : []
      when String, Symbol
        # Assume it's a scope name
        if model_class.respond_to?(relation_or_records)
          model_class.public_send(relation_or_records)
        else
          []
        end
      else
        relation_or_records
      end
    end

    def build_bulk_actions(batch, transform)
      batch.filter_map do |record|
        # Apply transform function if provided
        document = transform ? transform.call(record) : default_transform(record)
        next unless document

        {
          index: {
            _index: index_name,
            _id: extract_id(record),
            data: document
          }
        }
      rescue StandardError => e
        @errors << {
          error: e.message,
          record: identify_record(record)
        }
        nil
      end
    end

    def default_transform(record)
      if record.respond_to?(:to_h)
        record.to_h
      elsif record.respond_to?(:attributes)
        record.attributes
      else
        record
      end
    end

    def extract_id(record)
      if record.respond_to?(:id)
        record.id
      elsif record.is_a?(Hash)
        record[:id] || record["id"]
      else
        record.object_id
      end
    end

    def identify_record(record)
      id = extract_id(record)
      {
        id: id,
        class: record.class.name,
        object_id: record.object_id
      }
    end

    def collect_errors(response, batch)
      return unless response.is_a?(Hash) && response["items"]

      response["items"].each_with_index do |item, index|
        action = item.keys.first
        result = item[action]

        next unless result["error"]

        record = batch[index]
        @errors << {
          error: result["error"],
          record: identify_record(record),
          status: result["status"]
        }
      end
    end

    def index_name
      @index_name ||= if model_class.respond_to?(:search_index)
                        Array(model_class.search_index).first
                      else
                        model_class.name.demodulize.underscore.pluralize
                      end
    end

    def delete_index
      client = Noiseless.connections.client(@connection)
      client.delete_index(index_name)
    rescue StandardError => _e
      # Index might not exist, which is fine
      nil
    end

    def create_index
      return unless model_class.respond_to?(:mapping)

      mapping_block = model_class.mapping
      return unless mapping_block

      begin
        _client = Noiseless.connections.client(@connection)
        # This would need to be implemented in the adapter
        # client.create_index(index_name, mapping: mapping_block)
      rescue StandardError => e
        @errors << {
          error: "Failed to create index: #{e.message}",
          index: index_name
        }
      end
    end
  end
end
