# frozen_string_literal: true

module Noiseless
  module AST
    class Paginate < Node
      attr_reader :page, :per_page

      def initialize(page, per_page)
        super()
        @page = page
        @per_page = per_page
      end
    end
  end
end
