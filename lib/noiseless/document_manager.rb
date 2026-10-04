# frozen_string_literal: true

module Noiseless
  class DocumentManager
    def initialize(model_instance, connection: nil)
      @model_instance = model_instance
      @connection = connection || model_instance.class.connection
    end

    def index_document(refresh: false, **)
      document = build_document
      return false unless document

      await { client.index_document(index: index_name, id: document_id, document: document, refresh: refresh, **) }
    end

    def update_document(refresh: false, detect_changes: true, **)
      if detect_changes && supports_dirty_tracking?
        return false unless has_changes?

        changes = extract_changes
        return false if changes.empty?

        await { client.update_document(index: index_name, id: document_id, changes: changes, refresh: refresh, **) }
      else
        # Fall back to full document update
        index_document(refresh: refresh, **)
      end
    end

    def delete_document(refresh: false, **)
      await { client.delete_document(index: index_name, id: document_id, refresh: refresh, **) }
    end

    def document_exists?
      await { client.document_exists?(index: index_name, id: document_id) }
    end

    private

    def client = Noiseless.connections.client(@connection)

    def await = Sync { yield.wait }

    attr_reader :model_instance

    def build_document
      document = if model_instance.respond_to?(:to_search_document)
                   model_instance.to_search_document
                 elsif model_instance.respond_to?(:to_h)
                   model_instance.to_h
                 elsif model_instance.respond_to?(:attributes)
                   model_instance.attributes
                 end
      document && Embedding.wrap(document, vector_fields)
    end

    def vector_fields
      @vector_fields ||= Embedding.vector_fields(model_instance.class)
    end

    def document_id
      if model_instance.respond_to?(:id)
        model_instance.id
      elsif model_instance.respond_to?(:[])
        model_instance[:id] || model_instance["id"]
      else
        model_instance.object_id
      end
    end

    def index_name
      @index_name ||= if model_instance.class.respond_to?(:search_index)
                        Array(model_instance.class.search_index).first
                      else
                        model_instance.class.name.demodulize.underscore.pluralize
                      end
    end

    def supports_dirty_tracking?
      model_instance.respond_to?(:changed_attributes) ||
        model_instance.respond_to?(:changes) ||
        model_instance.respond_to?(:changed?)
    end

    def has_changes?
      return true unless supports_dirty_tracking?

      if model_instance.respond_to?(:changed?)
        model_instance.changed?
      elsif model_instance.respond_to?(:changes)
        !model_instance.changes.empty?
      elsif model_instance.respond_to?(:changed_attributes)
        !model_instance.changed_attributes.empty?
      else
        true
      end
    end

    def extract_changes
      changes = {}

      if model_instance.respond_to?(:changes)
        # ActiveModel::Dirty style changes hash
        model_instance.changes.each do |attr, (_old_value, new_value)|
          changes[attr] = new_value
        end
      elsif model_instance.respond_to?(:changed_attributes)
        # Get current values for changed attributes
        model_instance.changed_attributes.each_key do |attr|
          if model_instance.respond_to?(attr)
            changes[attr] = model_instance.public_send(attr)
          elsif model_instance.respond_to?(:[])
            changes[attr] = model_instance[attr]
          end
        end
      end

      Embedding.wrap(changes, vector_fields)
    end
  end
end
