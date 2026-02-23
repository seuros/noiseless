# frozen_string_literal: true

module Noiseless
  module AST
    # Image search node for Typesense visual search
    # Supports searching by image URL or base64 encoded image data
    class ImageQuery < Node
      attr_reader :field, :image_data, :k

      # @param field [Symbol, String] The image embedding field name
      # @param image_data [String] Image URL or base64 encoded image data
      # @param k [Integer] Number of nearest neighbors (default: 10)
      def initialize(field, image_data, k: 10)
        super()
        @field = field
        @image_data = image_data
        @k = k
      end

      def url?
        @image_data.start_with?("http://", "https://")
      end

      def base64?
        !url?
      end
    end
  end
end
