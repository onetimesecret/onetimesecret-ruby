# frozen_string_literal: true

require_relative "configuration"
require_relative "transport"
require_relative "ownership"
require_relative "resources/secrets"
require_relative "resources/receipts"

module Onetime
  # The main entry point for the OnetimeSecret API client.
  #
  #   client = Onetime::Client.new(
  #     base_url:     "https://ca.onetimesecret.com",
  #     customer:     "ur1abc23def", # customer extid
  #     api_token:    ENV["ONETIME_API_TOKEN"],
  #     api_version:  :v2,           # :v1 or :v2
  #   )
  #
  #   client.secrets.conceal(secret: "hunter2", ttl: 3600)
  #   client.receipts.recent
  #   client.status
  #
  # A client is safe to share across threads: it holds configuration, a
  # stateless transport, and a mutex-guarded flag for the once-only unowned
  # warning, and creates a fresh Net::HTTP connection per request.
  class Client
    # Explains a successful-but-unowned response. Deliberately detailed: it is
    # the only signal the caller gets that their credentials were ignored.
    UNOWNED_WARNING = <<~MSG.gsub("\n", " ").strip
      The server recorded this secret as anonymous even though this client sent
      credentials, so it has no owner and will not appear in your account. The
      credentials were most likely not accepted: check that `customer` is your
      customer extid (the "ur…" identifier at the bottom of the user menu) and
      that the API token belongs to it. Pass `on_unowned: :raise` to turn this
      into an exception, or `:ignore` to silence it.
    MSG

    attr_reader :config, :transport

    # Accepts the same keyword arguments as Onetime::Configuration, or an
    # already-built Configuration via `config:`.
    def initialize(config: nil, **options)
      @config = config || Configuration.new(**options)
      @config.validate!
      @transport = @config.transport || Transport.new(@config)
      @unowned_warned = false
      @unowned_lock = Mutex.new
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
      response = transport.request(
        method, full_path(path),
        query: query, body: body, form: form, raise_on_error: raise_on_error
      )
      check_ownership(response, path)
      response
    end

    private

    def full_path(path)
      "#{config.api_path_prefix}#{path}"
    end

    # Catches servers that accept unusable credentials instead of rejecting
    # them: a 2xx record marked anonymous, from a client that sent
    # credentials, means those credentials did nothing. Guest routes are
    # exempt — being ownerless is the point of asking for one.
    def check_ownership(response, path)
      return if config.on_unowned == :ignore
      return if config.anonymous? || path.to_s.include?("/guest/")
      return unless response.respond_to?(:success?) && response.success?
      return unless Ownership.unowned?(response)

      if config.on_unowned == :raise
        raise UnownedResponseError.new(UNOWNED_WARNING, response: response)
      end

      warn_unowned
    end

    # Warns once per client rather than once per request, to keep a long-lived
    # process from filling its log. The claim-and-set is synchronized so
    # concurrent requests on a shared client warn exactly once.
    def warn_unowned
      claimed = @unowned_lock.synchronize do
        @unowned_warned ? false : (@unowned_warned = true)
      end
      return unless claimed

      message = "[onetime] #{UNOWNED_WARNING}"
      config.logger ? config.logger.warn(message) : Kernel.warn(message)
    end

    def require_version!(expected, operation)
      return if api_version == expected

      raise UnsupportedOperationError,
            "#{operation} is only available on API #{expected}; client is configured for #{api_version}"
    end
  end
end
