# frozen_string_literal: true

require "uri"

module Onetime
  # Immutable-ish configuration for a Client instance.
  #
  # Values fall back to environment variables for drop-in compatibility
  # with the historical CLI/library:
  #   ONETIME_HOST    -> base_url
  #   ONETIME_CUSTID  -> username
  #   ONETIME_APIKEY  -> api_token
  class Configuration
    DEFAULT_BASE_URL     = "https://onetimesecret.com"
    DEFAULT_API_VERSION  = :v2
    SUPPORTED_VERSIONS   = %i[v1 v2].freeze
    DEFAULT_TIMEOUT      = 30  # read timeout, seconds
    DEFAULT_OPEN_TIMEOUT = 10  # connect timeout, seconds
    DEFAULT_MAX_RETRIES  = 2   # retries for idempotent requests

    attr_accessor :base_url, :api_version, :username, :api_token,
                  :timeout, :open_timeout, :max_retries,
                  :user_agent, :logger, :transport, :default_headers

    def initialize(base_url: nil, api_version: nil, username: nil, api_token: nil,
                   timeout: nil, open_timeout: nil, max_retries: nil,
                   user_agent: nil, logger: nil, transport: nil, default_headers: nil)
      @base_url        = base_url || ENV["ONETIME_HOST"] || DEFAULT_BASE_URL
      @api_version     = normalize_version(api_version || DEFAULT_API_VERSION)
      @username        = username || ENV["ONETIME_CUSTID"]
      @api_token       = api_token || ENV["ONETIME_APIKEY"]
      @timeout         = timeout || DEFAULT_TIMEOUT
      @open_timeout    = open_timeout || DEFAULT_OPEN_TIMEOUT
      @max_retries     = max_retries.nil? ? DEFAULT_MAX_RETRIES : max_retries
      @user_agent      = user_agent
      @logger          = logger
      @transport       = transport
      @default_headers = default_headers || {}
    end

    # True when no credentials are configured. Anonymous clients can still
    # use public and /guest/* endpoints.
    def anonymous?
      username.to_s.empty? && api_token.to_s.empty?
    end

    # The mount prefix for the configured API version, e.g. "/api/v2".
    def api_path_prefix
      "/api/#{api_version}"
    end

    def validate!
      unless SUPPORTED_VERSIONS.include?(api_version)
        raise ConfigurationError,
              "Unsupported api_version #{api_version.inspect}; supported: #{SUPPORTED_VERSIONS.join(', ')}"
      end

      begin
        uri = URI.parse(base_url)
      rescue URI::InvalidURIError => e
        raise ConfigurationError, "Invalid base_url #{base_url.inspect}: #{e.message}"
      end

      unless uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
        raise ConfigurationError, "base_url must be an absolute http(s) URL, got #{base_url.inspect}"
      end

      # Partial credentials are almost always a mistake; fail loudly.
      if username.to_s.empty? ^ api_token.to_s.empty?
        missing = username.to_s.empty? ? "username" : "api_token"
        raise ConfigurationError, "Incomplete credentials: #{missing} is missing"
      end

      self
    end

    private

    def normalize_version(version)
      case version
      when Symbol then version
      when String then version.start_with?("v") ? version.to_sym : :"v#{version}"
      when Integer then :"v#{version}"
      else version
      end
    end
  end
end
