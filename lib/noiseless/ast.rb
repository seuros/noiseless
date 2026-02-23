# frozen_string_literal: true

module Noiseless
  module AST
    class Node
      def to_h
        hash = {}
        instance_variables.each do |var|
          key = var.to_s.delete("@").to_sym
          value = instance_variable_get(var)

          hash[key] = case value
                      when Node
                        value.to_h
                      when Array
                        value.map { |item| item.is_a?(Node) ? item.to_h : item }
                      else
                        value
                      end
        end

        # Include the class name for better introspection
        hash[:_type] = self.class.name.split("::").last
        hash
      end

      alias to_hash to_h
    end
  end
end
