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
  # The extid is not an internal record UUID and not an email address; both
  # are rejected by #validate! with a message naming the mistake, because
  # both otherwise fail as an opaque 401 (or, worse, as a secret the server
  # quietly records as anonymous — see Onetime::Ownership).
  #
  # Values fall back to environment variables:
  #   ONETIME_BASE_URL    -> base_url
  #   ONETIME_ORG_EXTID   -> organization
  #   ONETIME_API_TOKEN   -> api_token
  class Configuration
    DEFAULT_API_VERSION  = :v2
    SUPPORTED_VERSIONS   = %i[v1 v2].freeze
    DEFAULT_TIMEOUT      = 30  # read timeout, seconds
    DEFAULT_OPEN_TIMEOUT = 10  # connect timeout, seconds
    DEFAULT_MAX_RETRIES  = 2   # retries for idempotent requests
    DEFAULT_ON_UNOWNED   = :warn # see #on_unowned

    # What to do when a request made *with* credentials comes back describing
    # a record the server recorded as anonymous — the signature of credentials
    # that were sent but not honoured.
    ON_UNOWNED_MODES = %i[warn raise ignore].freeze

    # An organization extid is a short, opaque, case-insensitive identifier
    # that always begins with "on" — e.g. "on1abc23def". It is neither a
    # UUID (internal record id) nor an email address; both are common
    # mix-ups, and both are rejected below with a message that says so.
    ORG_EXTID_PATTERN = /\Aon[a-z0-9]+\z/i

    # Internal record ids, which are *not* usable as credentials. Matched
    # with and without dashes since both forms get pasted.
    UUID_PATTERN = /\A\h{8}-?\h{4}-?\h{4}-?\h{4}-?\h{12}\z/

    # Where to find the real value. Repeated in every rejection message
    # because "invalid organization" without this is a support ticket.
    ORG_EXTID_HINT =
      'Your organization extid is the "on…" identifier at the bottom of the ' \
      "user menu when you are signed in (there is a copy button next to it). " \
      "Pass it as organization: or set ONETIME_ORG_EXTID."

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

    attr_accessor :base_url, :api_version, :organization, :api_token,
                  :timeout, :open_timeout, :max_retries,
                  :user_agent, :logger, :transport, :default_headers,
                  :on_unowned

    def initialize(base_url: nil, api_version: nil, organization: nil,
                   api_token: nil, timeout: nil, open_timeout: nil, max_retries: nil,
                   user_agent: nil, logger: nil, transport: nil, default_headers: nil,
                   on_unowned: nil)
      @base_url        = base_url || ENV["ONETIME_BASE_URL"]
      @api_version     = normalize_version(api_version || DEFAULT_API_VERSION)
      @organization    = organization || ENV["ONETIME_ORG_EXTID"]
      @api_token       = api_token || ENV["ONETIME_API_TOKEN"]
      @timeout         = timeout || DEFAULT_TIMEOUT
      @open_timeout    = open_timeout || DEFAULT_OPEN_TIMEOUT
      @max_retries     = max_retries.nil? ? DEFAULT_MAX_RETRIES : max_retries
      @user_agent      = user_agent
      @logger          = logger
      @transport       = transport
      @default_headers = default_headers || {}
      @on_unowned      = (on_unowned || DEFAULT_ON_UNOWNED).to_sym
    end

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
      validate_on_unowned!
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
      validate_organization_format! unless organization.to_s.empty?

      # Partial credentials are almost always a mistake; fail loudly.
      return unless organization.to_s.empty? ^ api_token.to_s.empty?

      missing = organization.to_s.empty? ? "organization" : "api_token"
      raise ConfigurationError, "Incomplete credentials: #{missing} is missing"
    end

    # Catch the wrong-identifier mistake at construction time rather than as a
    # 401 — or worse, as a silently unowned secret — several calls later.
    def validate_organization_format!
      value = organization.to_s
      return if ORG_EXTID_PATTERN.match?(value)

      raise ConfigurationError,
            "#{organization_rejection_reason(value)} #{ORG_EXTID_HINT}"
    end

    def organization_rejection_reason(value)
      if UUID_PATTERN.match?(value)
        "organization #{value.inspect} looks like an internal record UUID, " \
          "not an organization extid. UUIDs appear in API payloads and admin " \
          "tooling but are not credentials."
      elsif value.include?("@")
        "organization #{value.inspect} looks like an email address. Email " \
          "addresses (the pre-1.0 custid) are no longer used to authenticate."
      else
        "organization #{value.inspect} is not an organization extid: extids " \
          'begin with "on" (e.g. "on1abc23def").'
      end
    end

    def validate_on_unowned!
      return if ON_UNOWNED_MODES.include?(on_unowned)

      raise ConfigurationError,
            "Unsupported on_unowned #{on_unowned.inspect}; " \
            "supported: #{ON_UNOWNED_MODES.join(', ')}"
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
