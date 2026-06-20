# frozen_string_literal: true

require_relative "test_helper"
require "socket"

# Exercises the real Net::HTTP transport against a one-shot TCP server, so
# URL building, headers, auth, body serialization and response parsing are
# all validated end-to-end without an external mocking library.
class TransportIntegrationTest < Minitest::Test
  def setup
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @request_line = nil
    @headers = {}
    @request_body = nil

    @thread = Thread.new do
      socket = @server.accept
      @request_line = socket.gets
      while (line = socket.gets) && line != "\r\n"
        key, value = line.chomp.split(": ", 2)
        @headers[key.downcase] = value
      end
      if (len = @headers["content-length"])
        @request_body = socket.read(len.to_i)
      end

      body = JSON.generate({ "record" => { "secret" => { "secret_value" => "hi" } } })
      socket.write("HTTP/1.1 200 OK\r\n")
      socket.write("Content-Type: application/json\r\n")
      socket.write("Content-Length: #{body.bytesize}\r\n")
      socket.write("Connection: close\r\n\r\n")
      socket.write(body)
      socket.close
    end
  end

  def teardown
    @thread.join(2)
    @server.close
  end

  def client(**opts)
    Onetime::Client.new(
      base_url: "http://127.0.0.1:#{@port}",
      api_version: :v2,
      organization: "on1example",
      api_token: "token123",
      **opts
    )
  end

  def test_post_json_with_basic_auth_and_parsed_response
    res = client.secrets.conceal(secret: "hunter2", ttl: 3600)
    @thread.join(2)

    assert_equal "POST /api/v2/secret/conceal HTTP/1.1", @request_line.chomp
    assert_equal "application/json", @headers["content-type"]
    assert_equal "application/json", @headers["accept"]
    # HTTP Basic: organization extid in the username slot, token as password.
    # base64("on1example:token123")
    expected_auth = "Basic #{["on1example:token123"].pack('m0')}"
    assert_equal expected_auth, @headers["authorization"]
    assert_match %r{onetime-ruby/}, @headers["user-agent"]
    assert_match %r{\Aruby:}, @headers["x-onetime-client"]

    assert_equal({ "secret" => { "secret" => "hunter2", "ttl" => 3600 } }, JSON.parse(@request_body))
    assert_equal "hi", res.dig("record", "secret", "secret_value")
    assert res.success?
  end
end

# A 4xx response in ADR-013 shape must raise the mapped exception.
class TransportErrorPathTest < Minitest::Test
  def setup
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @thread = Thread.new do
      socket = @server.accept
      socket.gets
      while (line = socket.gets) && line != "\r\n"; end
      body = JSON.generate({ "error" => "No such secret", "error_type" => "RecordNotFound" })
      socket.write("HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\n")
      socket.write("Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      socket.close
    end
  end

  def teardown
    @thread.join(2)
    @server.close
  end

  def test_raises_not_found_error
    client = Onetime::Client.new(base_url: "http://127.0.0.1:#{@port}", api_version: :v2)
    err = assert_raises(Onetime::NotFoundError) { client.secrets.show("missing") }
    assert_equal "No such secret", err.message
    assert_equal 404, err.http_status
    assert_equal "RecordNotFound", err.error_type
  end
end

# Anonymous requests must not send an Authorization header.
class TransportAnonymousTest < Minitest::Test
  def setup
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @headers = {}
    @thread = Thread.new do
      socket = @server.accept
      socket.gets
      while (line = socket.gets) && line != "\r\n"
        key, value = line.chomp.split(": ", 2)
        @headers[key.downcase] = value
      end
      body = "{}"
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n")
      socket.write("Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      socket.close
    end
  end

  def teardown
    @thread.join(2)
    @server.close
  end

  def test_no_auth_header_when_anonymous
    Onetime::Client.new(
      base_url: "http://127.0.0.1:#{@port}", api_version: :v2
    ).status
    @thread.join(2)

    assert_nil @headers["authorization"]
  end
end
