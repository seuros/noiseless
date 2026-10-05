# frozen_string_literal: true

module Noiseless
  # Log subscriber for Rails integration
  class LogSubscriber < ActiveSupport::LogSubscriber
    def search(event)
      return unless logger.debug?

      indexes = event.payload[:indexes]&.join(", ") || "unknown"
      duration = event.duration.round(2)

      debug "Noiseless Search (#{duration}ms) indexes=[#{indexes}] #{query_summary(event.payload[:query])}"
    end

    def bulk(event)
      return unless logger.debug?

      actions_count = event.payload[:actions_count] || 0
      duration = event.duration.round(2)

      debug "Noiseless Bulk (#{duration}ms) actions=#{actions_count}"
    end

    def index_document(event)
      return unless logger.debug?

      index = event.payload[:index]
      id = event.payload[:id]
      duration = event.duration.round(2)

      debug "Noiseless Index Document (#{duration}ms) index=#{index} id=#{id}"
    end

    def update_document(event)
      return unless logger.debug?

      index = event.payload[:index]
      id = event.payload[:id]
      changes_count = event.payload[:changes_count] || 0
      duration = event.duration.round(2)

      debug "Noiseless Update Document (#{duration}ms) index=#{index} id=#{id} changes=#{changes_count}"
    end

    def delete_document(event)
      return unless logger.debug?

      index = event.payload[:index]
      id = event.payload[:id]
      duration = event.duration.round(2)

      debug "Noiseless Delete Document (#{duration}ms) index=#{index} id=#{id}"
    end

    def create_index(event)
      return unless logger.debug?

      index = event.payload[:index]
      duration = event.duration.round(2)

      debug "Noiseless Create Index (#{duration}ms) index=#{index}"
    end

    def delete_index(event)
      return unless logger.debug?

      index = event.payload[:index]
      duration = event.duration.round(2)

      debug "Noiseless Delete Index (#{duration}ms) index=#{index}"
    end

    private

    def query_summary(query)
      return "empty" unless query.is_a?(Hash)

      parts = []

      if query[:query]&.dig(:bool, :must)&.any?
        must_count = query[:query][:bool][:must].size
        parts << "must:#{must_count}"
      end

      if query[:query]&.dig(:bool, :filter)&.any?
        filter_count = query[:query][:bool][:filter].size
        parts << "filter:#{filter_count}"
      end

      if query[:sort]&.any?
        sort_count = query[:sort].size
        parts << "sort:#{sort_count}"
      end

      if query[:from] || query[:size]
        parts << "from:#{query[:from] || 0}"
        parts << "size:#{query[:size] || 20}"
      end

      parts.join(" ")
    end
  end
end
