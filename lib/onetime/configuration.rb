# frozen_string_literal: true

require "uri"

module Onetime
  # Immutable-ish configuration for a Client instance.
  #
  # Authentication uses HTTP Basic, where the username slot carries the
  # *organization external id* (extid) — the identifier that begins with
  # "on" and is shown (with a copy button) at the bottom of the user menu
  # when signed in. The password slot carries your API token.
  #
  # Values fall back to environment variables:
  #   ONETIME_BASE_URL / ONETIME_HOST     -> base_url
  #   ONETIME_ORG_EXTID / ONETIME_CUSTID  -> organization
  #   ONETIME_API_TOKEN / ONETIME_APIKEY  -> api_token
  class Configuration
    DEFAULT_API_VERSION  = :v2
    SUPPORTED_VERSIONS   = %i[v1 v2].freeze
    DEFAULT_TIMEOUT      = 30  # read timeout, seconds
    DEFAULT_OPEN_TIMEOUT = 10  # connect timeout, seconds
    DEFAULT_MAX_RETRIES  = 2   # retries for idempotent requests

    # The apex domain and its www host serve the company website, not the
    # API. Regional deployments each have their own host.
    APEX_HOSTS = %w[onetimesecret.com www.onetimesecret.com].freeze

    # Known regional API hosts (per the API's published server list),
    # surfaced in error messages. Self-hosted and custom domains are also
    # valid base URLs.
    EXAMPLE_REGIONAL_HOSTS = %w[
      us.onetimesecret.com eu.onetimesecret.com uk.onetimesecret.com
      ca.onetimesecret.com nz.onetimesecret.com
    ].freeze

    attr_accessor :base_url, :api_version, :api_token,
                  :timeout, :open_timeout, :max_retries,
                  :user_agent, :logger, :transport, :default_headers

    # The HTTP Basic username value (the organization extid).
    attr_reader :organization

    def initialize(base_url: nil, api_version: nil, organization: nil, username: nil,
                   api_token: nil, timeout: nil, open_timeout: nil, max_retries: nil,
                   user_agent: nil, logger: nil, transport: nil, default_headers: nil)
      @base_url        = base_url || ENV["ONETIME_BASE_URL"] || ENV["ONETIME_HOST"]
      @api_version     = normalize_version(api_version || DEFAULT_API_VERSION)
      # `username` is accepted as a backward-compatible alias for `organization`.
      @organization    = organization || username ||
                         ENV["ONETIME_ORG_EXTID"] || ENV["ONETIME_CUSTID"]
      @api_token       = api_token || ENV["ONETIME_API_TOKEN"] || ENV["ONETIME_APIKEY"]
      @timeout         = timeout || DEFAULT_TIMEOUT
      @open_timeout    = open_timeout || DEFAULT_OPEN_TIMEOUT
      @max_retries     = max_retries.nil? ? DEFAULT_MAX_RETRIES : max_retries
      @user_agent      = user_agent
      @logger          = logger
      @transport       = transport
      @default_headers = default_headers || {}
    end

    # Backward-compatible alias: the organization extid occupies the HTTP
    # Basic username slot.
    def organization=(value)
      @organization = value
    end
    alias username organization
    alias username= organization=

    # True when no credentials are configured. Anonymous clients can still
    # use public and /guest/* endpoints.
    def anonymous?
      organization.to_s.empty? && api_token.to_s.empty?
    end

    # The mount prefix for the configured API version, e.g. "/api/v2".
    def api_path_prefix
      "/api/#{api_version}"
    end

    def validate!
      validate_api_version!
      validate_base_url!
      validate_credentials!
      self
    end

    private

    def validate_api_version!
      return if SUPPORTED_VERSIONS.include?(api_version)

      raise ConfigurationError,
            "Unsupported api_version #{api_version.inspect}; supported: #{SUPPORTED_VERSIONS.join(', ')}"
    end

    def validate_base_url!
      if base_url.to_s.empty?
        examples = EXAMPLE_REGIONAL_HOSTS.first(3).map { |h| "https://#{h}" }.join(", ")
        raise ConfigurationError,
              "base_url is required. Use your region's API host " \
              "(e.g. #{examples}), your self-hosted domain, or your custom " \
              "domain. Set it via the base_url: option or the ONETIME_BASE_URL " \
              "environment variable."
      end

      begin
        uri = URI.parse(base_url)
      rescue URI::InvalidURIError => e
        raise ConfigurationError, "Invalid base_url #{base_url.inspect}: #{e.message}"
      end

      unless uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
        raise ConfigurationError, "base_url must be an absolute http(s) URL, got #{base_url.inspect}"
      end

      return unless APEX_HOSTS.include?(uri.host.downcase)

      raise ConfigurationError,
            "#{uri.host} is the OneTimeSecret company website, not an API host. " \
            "Use a regional subdomain (e.g. https://#{EXAMPLE_REGIONAL_HOSTS.first}), " \
            "your self-hosted domain, or your custom domain."
    end

    def validate_credentials!
      # Partial credentials are almost always a mistake; fail loudly.
      return unless organization.to_s.empty? ^ api_token.to_s.empty?

      missing = organization.to_s.empty? ? "organization" : "api_token"
      raise ConfigurationError, "Incomplete credentials: #{missing} is missing"
    end

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
