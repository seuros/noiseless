# frozen_string_literal: true

module Noiseless
  module DSL
    module ClassMethods
      def search_index(*names)
        @index_names = names.flatten.map(&:to_s) if names.any?
        @index_names
      end

      def index_name(name = nil)
        @index_name = name.to_s if name
        @index_name
      end

      def searchable_fields(*fields)
        @searchable_fields = fields if fields.any?
        @searchable_fields
      end

      def adapter(name = nil)
        @adapter_name = name if name
        @adapter_name || Noiseless.config.default_adapter
      end

      def connection(name = nil)
        @connection_name = name if name
        @connection_name || Noiseless.config.default_connection
      end

      def mapping(&block)
        @mapping_block = block if block
        @mapping_block
      end

      def import(*, **)
        BulkImporter.new(self).import(*, **)
      end

      def import_scoped(scope, **)
        BulkImporter.new(self).import_scoped(scope, **)
      end

      def reindex(**)
        BulkImporter.new(self).reindex(**)
      end

      def bulk_importer(connection: nil)
        BulkImporter.new(self, connection: connection)
      end

      def searchable(**)
        include Callbacks unless included_modules.include?(Callbacks)
        include DSL::InstanceMethods unless included_modules.include?(DSL::InstanceMethods)

        auto_index(true, **)

        # Register the model in the global registry
        Noiseless.register_model(self, searchable: true, **)
      end

      def multi_search(models: nil, indexes: nil, connection: nil, &block)
        search_instance = MultiSearch.new(
          models: models || [self],
          indexes: indexes,
          connection: connection || self.connection
        )

        if block
          search_instance.search(&block)
        else
          search_instance
        end
      end

      def page(num = nil)
        Pagination::SearchPaginator.new(self, page: num)
      end

      def per(num)
        Pagination::SearchPaginator.new(self, per_page: num)
      end
    end

    module InstanceMethods
      def index_document(**)
        DocumentManager.new(self).index_document(**)
      end

      def update_document(**)
        DocumentManager.new(self).update_document(**)
      end

      def delete_document(**)
        DocumentManager.new(self).delete_document(**)
      end

      def document_exists?
        DocumentManager.new(self).document_exists?
      end

      def document_manager(connection: nil)
        DocumentManager.new(self, connection: connection)
      end
    end
  end
end
