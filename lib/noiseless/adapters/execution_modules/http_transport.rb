# frozen_string_literal: true

module Noiseless
  module Adapters
    module ExecutionModules
      # Shared Async::HTTP connection handling for HTTP-based adapters.
      # Host classes must provide a private +default_port+ method.
      module HttpTransport
        def initialize(hosts: [], **connection_params)
          # Ensure we always have at least one host
          hosts_array = Array(hosts)
          @hosts = hosts_array.empty? ? ["http://localhost:#{default_port}"] : hosts_array
          @connection_params = connection_params

          # Initialize HTTP clients for each host
          @clients = {}
          @hosts.each do |host|
            endpoint = Async::HTTP::Endpoint.parse(host)
            @clients[host] = Async::HTTP::Client.new(endpoint)
          end

          super(hosts: @hosts, **connection_params)
        end

        def close
          @clients&.each_value(&:close)
        end

        private

        # HTTP helpers using Async::HTTP with connection pooling
        def get_request(path)
          with_client do |client|
            client.get(path, default_headers)
          end
        end

        def post_request(path, body, content_type: "application/json")
          headers = body ? default_headers + [["content-type", content_type]] : default_headers

          with_client do |client|
            client.post(path, headers, body)
          end
        end

        def put_request(path, body, content_type: "application/json")
          headers = body ? default_headers + [["content-type", content_type]] : default_headers

          with_client do |client|
            client.put(path, headers, body)
          end
        end

        def delete_request(path)
          with_client do |client|
            client.delete(path, default_headers)
          end
        end

        def head_request(path)
          with_client do |client|
            client.head(path, default_headers)
          end
        end

        def with_client
          # Select a random host for load balancing
          host = @hosts.sample
          client = @clients[host]

          yield(client)
        end

        def default_headers
          [
            ["accept", "application/json"],
            ["user-agent", "Noiseless/#{Noiseless::VERSION} (Ruby/#{RUBY_VERSION})"]
          ]
        end
      end
    end
  end
end
