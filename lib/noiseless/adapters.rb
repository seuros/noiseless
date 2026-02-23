# frozen_string_literal: true

module Noiseless
  module Adapters
    def self.lookup(name, hosts: [], **params)
      adapter_name = name.to_s
      class_name = adapter_name.classify

      # Zeitwerk will load the adapter class on demand
      adapter_class = const_get(class_name)
      adapter_class.new(hosts: hosts, **params)
    end
  end
end
