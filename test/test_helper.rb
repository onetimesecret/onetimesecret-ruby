# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "onetime"

# A transport double that records the last request and returns a canned
# Response. Lets us assert on method/path/body/form without any network or
# external mocking library.
class FakeTransport
  Call = Struct.new(:method, :path, :query, :body, :form, :raise_on_error, keyword_init: true)

  attr_reader :calls
  attr_accessor :next_response

  def initialize(status: 200, data: {})
    @calls = []
    @next_response = Onetime::Response.new(
      http_status: status, headers: {}, raw_body: "", data: data
    )
  end

  def request(method, path, query: nil, body: nil, form: nil, raise_on_error: true)
    @calls << Call.new(
      method: method, path: path, query: query, body: body, form: form,
      raise_on_error: raise_on_error
    )
    @next_response
  end

  def last
    @calls.last
  end
end

module ClientTestHelpers
  def build_client(version:, transport: FakeTransport.new, **opts)
    Onetime::Client.new(
      api_version: version,
      username: "user@example.com",
      api_token: "token123",
      transport: transport,
      **opts
    )
  end
end
