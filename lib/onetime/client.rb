# frozen_string_literal: true

require_relative "configuration"
require_relative "transport"
require_relative "resources/secrets"
require_relative "resources/receipts"

module Onetime
  # The main entry point for the OnetimeSecret API client.
  #
  #   client = Onetime::Client.new(
  #     base_url:     "https://us.onetimesecret.com",
  #     organization: "on1abc...",
  #     api_token:    ENV["ONETIME_API_TOKEN"],
  #     api_version:  :v2,           # :v1 or :v2
  #   )
  #
  #   client.secrets.conceal(secret: "hunter2", ttl: 3600)
  #   client.receipts.recent
  #   client.status
  #
  # A client is safe to share across threads: it holds only configuration and
  # a stateless transport, and creates a fresh Net::HTTP connection per request.
  class Client
    attr_reader :config, :transport

    # Accepts the same keyword arguments as Onetime::Configuration, or an
    # already-built Configuration via `config:`.
    def initialize(config: nil, **options)
      @config = config || Configuration.new(**options)
      @config.validate!
      @transport = @config.transport || Transport.new(@config)
    end

    def api_version
      config.api_version
    end

    # Secret resource accessor (conceal/generate/reveal/show/status).
    def secrets
      @secrets ||= Resources::Secrets.new(self)
    end

    # Receipt resource accessor (show/recent/burn/update).
    def receipts
      @receipts ||= Resources::Receipts.new(self)
    end

    # --- Meta / public endpoints -------------------------------------------

    # Service status. Available on both v1 and v2.
    def status
      request(:get, "/status")
    end

    # Service version. (v2 only)
    def version
      require_version!(:v2, "version")
      request(:get, "/version")
    end

    # Locales supported by the service. (v2 only)
    def supported_locales
      require_version!(:v2, "supported_locales")
      request(:get, "/supported-locales")
    end

    # Verify the configured credentials are valid. (v1 only)
    def authcheck
      require_version!(:v1, "authcheck")
      request(:get, "/authcheck")
    end

    # --- Low-level request helper ------------------------------------------

    # Issue a request against the configured API version. The path is
    # relative to the version prefix (e.g. "/secret/conceal").
    #
    # @return [Onetime::Response]
    def request(method, path, query: nil, body: nil, form: nil, raise_on_error: true)
      transport.request(
        method, full_path(path),
        query: query, body: body, form: form, raise_on_error: raise_on_error
      )
    end

    private

    def full_path(path)
      "#{config.api_path_prefix}#{path}"
    end

    def require_version!(expected, operation)
      return if api_version == expected

      raise UnsupportedOperationError,
            "#{operation} is only available on API #{expected}; client is configured for #{api_version}"
    end
  end
end
