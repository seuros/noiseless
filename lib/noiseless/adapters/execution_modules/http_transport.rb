# frozen_string_literal: true

require "socket"
require "timeout"

module Noiseless
  module Adapters
    module ExecutionModules
      # Shared Async::HTTP connection handling for HTTP-based adapters.
      # Host classes must provide a private +default_port+ method.
      module HttpTransport
        # Low-level failures the Async::HTTP stack raises when it cannot
        # complete a round-trip with the backend (refused/reset connection,
        # DNS failure, transport timeout). These are wrapped into
        # Noiseless::ConnectionError so callers never have to know which HTTP
        # stack is underneath.
        TRANSPORT_ERRORS = [
          SystemCallError,
          SocketError,
          IOError,
          IO::TimeoutError,
          Timeout::Error,
          Protocol::HTTP::Error
        ].freeze

        # Default per-operation IO timeout (seconds) for the search backend.
        # This is an *idle* timeout: every socket read/write must make progress
        # within this window. It bounds a stalled/unresponsive backend without
        # capping the total duration of streaming operations (e.g. bulk import),
        # since data keeps flowing during those. Override per-connection with
        # +timeout:+.
        DEFAULT_TIMEOUT = 5

        # Default wall-clock deadline (seconds) for a complete round-trip:
        # request write, response headers, and full body. The idle timeout
        # above never trips against a backend that keeps trickling bytes —
        # each read makes "progress" — which leaves callers blocked in
        # Sync { ... .wait } indefinitely. This caps total duration instead.
        # Override per-connection with +request_timeout:+; nil disables the
        # deadline (long bulk imports may need a higher value or nil).
        DEFAULT_REQUEST_TIMEOUT = 30

        # Default cap on concurrent connections per host. Without it the pool
        # opens one socket per concurrent request. Waiting for a free
        # connection counts against request_timeout. Override per-connection
        # with +pool_limit:+.
        DEFAULT_POOL_LIMIT = 16

        # json 3 serializes objects it does not know with to_s, so a Time
        # became "2025-12-11 14:18:40 UTC", which search engines reject.
        # Falling back to as_json keeps ActiveSupport's ISO 8601 times.
        JSON_CODER = JSON::Coder.new { |object| object.respond_to?(:as_json) ? object.as_json : object.to_s }

        BufferedResponse = Data.define(:status, :body) do
          def read = body
          def success? = (200..299).cover?(status)
          def close = nil
        end

        def initialize(hosts: [], timeout: DEFAULT_TIMEOUT, request_timeout: DEFAULT_REQUEST_TIMEOUT,
                       pool_limit: DEFAULT_POOL_LIMIT, **connection_params)
          unless request_timeout.nil? || (request_timeout.is_a?(Numeric) && request_timeout.positive? && request_timeout.finite?)
            raise ArgumentError, "request_timeout must be a positive finite number or nil, got #{request_timeout.inspect}"
          end

          # Ensure we always have at least one host
          hosts_array = Array(hosts)
          @hosts = hosts_array.empty? ? ["http://localhost:#{default_port}"] : hosts_array
          @timeout = timeout
          @request_timeout = request_timeout
          @connection_params = connection_params

          # Initialize HTTP clients for each host. The endpoint timeout makes a
          # stalled backend raise IO::TimeoutError (wrapped below as
          # ConnectionError) instead of blocking the fiber/reactor indefinitely.
          @clients = {}
          @hosts.each do |host|
            endpoint = Async::HTTP::Endpoint.parse(host, timeout: @timeout)
            @clients[host] = Async::HTTP::Client.new(endpoint, limit: pool_limit)
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

        def post_request(path, body, content_type: "application/json") = body_request(:post, path, body, content_type)
        def put_request(path, body, content_type: "application/json") = body_request(:put, path, body, content_type)
        def patch_request(path, body, content_type: "application/json") = body_request(:patch, path, body, content_type)

        def body_request(verb, path, body, content_type)
          headers = body ? default_headers + [["content-type", content_type]] : default_headers

          with_client do |client|
            client.public_send(verb, path, headers, body)
          end
        end

        def delete_request(path, body = nil) = body_request(:delete, path, body, "application/json")

        def head_request(path)
          with_client do |client|
            client.head(path, default_headers)
          end
        end

        def with_client
          # Select a random host for load balancing
          host = @hosts.sample
          client = @clients[host]

          wrap_transport_errors(host: host) do
            with_request_deadline(host: host) do
              buffer_response(yield(client))
            end
          end
        end

        def with_request_deadline(host:, &)
          task = @request_timeout && Async::Task.current?
          return yield unless task

          task.with_timeout(@request_timeout, &)
        rescue Async::TimeoutError
          raise Noiseless::ConnectionError,
                "search backend at #{host} exceeded request_timeout (#{@request_timeout}s wall-clock)"
        end

        def buffer_response(response)
          BufferedResponse.new(response.status, response.read)
        ensure
          response.close
        end

        def parse_json_response!(response, error_class: Noiseless::RequestError, context: nil)
          wrap_transport_errors { super }
        end

        def wrap_transport_errors(host: nil)
          yield
        rescue *TRANSPORT_ERRORS => e
          location = host ? " at #{host}" : ""
          raise Noiseless::ConnectionError,
                "search backend unreachable#{location} (#{e.class}: #{e.message})"
        end

        def dump_json(object) = JSON_CODER.dump(object)

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
