# frozen_string_literal: true

# Backwards-compatibility shim for the pre-1.0 Onetime::API interface.
#
# Historically the library exposed:
#
#   require "onetime/api"
#   api = OT::API.new(ORG_EXTID, "APITOKEN", base_url: "https://us.onetimesecret.com")
#   api.get("/status")
#   api.post("/generate", passphrase: "secret")
#
# That surface is preserved here, delegating to the modern Onetime::Client
# so existing scripts keep working without HTTParty. New code should use
# Onetime::Client directly.
#
# Notable compatibility behaviours:
#   - the first positional argument is the organization extid (the "on..."
#     identifier shown at the bottom of the user menu), occupying the HTTP
#     Basic username slot. (Historically this was the email custid.)
#   - defaults to API v1 (the only version the old client spoke)
#   - base_url is required (apex onetimesecret.com is the company website,
#     not an API host); pass base_url: or set ONETIME_BASE_URL/ONETIME_HOST
#   - get/post take a path WITHOUT the /api/vN prefix (it is added for you)
#   - returns the parsed body Hash (indifferent access), not a Response
#   - does NOT raise on HTTP errors; inspect #response.code like before

require_relative "../onetime"

module Onetime
  class API
    module VERSION
      def self.to_s
        Onetime::VERSION
      end

      def self.to_a
        Onetime::VERSION.split(".")
      end

      def self.inspect
        Onetime::VERSION
      end
    end

    attr_reader :client, :response, :custid, :key, :anonymous, :default_params
    attr_accessor :apiversion

    def initialize(custid = nil, key = nil, opts = {})
      @apiversion = (opts.delete(:apiversion) || opts.delete("apiversion") || 1).to_i
      @default_params = {}

      # The first positional argument historically held the email custid; it
      # now holds the organization extid. Configuration resolves env fallbacks.
      @client = Onetime::Client.new(
        base_url:     opts[:base_url],
        api_version:  :"v#{@apiversion}",
        organization: custid,
        api_token:    key,
      )
      @custid    = @client.config.organization
      @key       = @client.config.api_token
      @anonymous = @client.config.anonymous?
    end

    def get(path, params = nil)
      @response = client.request(:get, path, query: merged(params), raise_on_error: false)
      @response.data
    end

    def post(path, params = nil)
      @response = client.request(:post, path, form: merged(params), raise_on_error: false)
      @response.data
    end

    private

    def merged(params)
      (params || {}).merge(default_params)
    end
  end
end
