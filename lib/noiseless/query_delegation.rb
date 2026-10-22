# frozen_string_literal: true

module Noiseless
  module QueryDelegation
    # Unlike ordinary delegation, fluent query methods return their wrapper.
    def delegate_query_methods(*names, to:)
      names.each do |name|
        define_method(name) do |*args, **options, &block|
          instance_variable_get(to).public_send(name, *args, **options, &block)
          self
        end
      end
    end
  end
end
