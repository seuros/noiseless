# frozen_string_literal: true

require "test_helper"
require "socket"

class HttpTransportTimeoutTest < ActiveSupport::TestCase
  # A backend that sends headers promptly, then trickles the body forever.
  # Each write arrives well within the idle timeout, so only a wall-clock
  # deadline can unblock the caller.
  def with_trickling_server(chunk_interval: 0.05)
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    thread = Thread.new do
      socket = server.accept
      socket.readpartial(4096)
      socket.write("HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: 1000\r\n\r\n")
      1000.times do
        socket.write("x")
        socket.flush
        sleep chunk_interval
      end
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      nil
    ensure
      socket&.close
    end
    yield port
  ensure
    thread&.kill
    server&.close
  end

  test "request_timeout unwedges a trickling backend the idle timeout never catches" do
    with_trickling_server do |port|
      adapter = Noiseless::Adapters.lookup(:open_search,
                                           hosts: ["http://127.0.0.1:#{port}"],
                                           timeout: 5, request_timeout: 0.5)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      error = assert_raises(Noiseless::ConnectionError) do
        Sync { adapter.search_raw({ query: { match_all: {} } }).wait }
      end
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert_match(/request_timeout/, error.message)
      assert_operator elapsed, :<, 3, "deadline should fire at ~0.5s, not wedge"
    ensure
      adapter&.close
    end
  end

  test "request_timeout: nil disables the wall-clock deadline" do
    adapter = Noiseless::Adapters.lookup(:open_search,
                                         hosts: ["http://127.0.0.1:1"],
                                         timeout: 1, request_timeout: nil)
    assert_nil adapter.instance_variable_get(:@request_timeout)
  ensure
    adapter&.close
  end

  test "connection manager forwards request_timeout to the adapter" do
    manager = Noiseless::ConnectionManager.new
    manager.register(:capped, adapter: :open_search, hosts: ["http://127.0.0.1:1"], request_timeout: 7)
    manager.register(:defaulted, adapter: :open_search, hosts: ["http://127.0.0.1:1"])

    assert_equal 7, manager.client(:capped).instance_variable_get(:@request_timeout)
    assert_equal Noiseless::Adapters::ExecutionModules::HttpTransport::DEFAULT_REQUEST_TIMEOUT,
                 manager.client(:defaulted).instance_variable_get(:@request_timeout)
  end

  test "rejects a non-finite request_timeout and caps connections per host" do
    assert_raises(ArgumentError) do
      Noiseless::Adapters.lookup(:open_search, hosts: ["http://127.0.0.1:1"], request_timeout: Float::INFINITY)
    end

    server = TCPServer.new("127.0.0.1", 0)
    connections = Thread::Queue.new
    acceptor = Thread.new do
      loop do
        socket = server.accept
        connections << socket
        Thread.new(socket) do |s|
          while s.gets("\r\n\r\n")
            sleep 0.05
            s.write("HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: 2\r\n\r\n{}")
          end
        rescue IOError, Errno::ECONNRESET
          nil
        end
      end
    end

    adapter = Noiseless::Adapters.lookup(:open_search, hosts: ["http://127.0.0.1:#{server.addr[1]}"], pool_limit: 4)
    Sync { Array.new(12) { Async { adapter.send(:get_request, "/") } }.each(&:wait) }

    assert_operator connections.size, :<=, 4
  ensure
    adapter&.close
    acceptor&.kill
    server&.close
  end
end
