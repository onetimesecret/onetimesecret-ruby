# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

require_relative "version"
require_relative "response"
require_relative "errors"

module Onetime
  # Zero-dependency HTTP transport built on stdlib Net::HTTP.
  #
  # Responsibilities:
  #   - build the request URL, headers and body (form for v1, JSON for v2)
  #   - apply HTTP Basic auth when credentials are configured
  #   - retry idempotent requests with exponential backoff
  #   - parse the JSON response and map error statuses to exceptions
  #
  # It intentionally has no knowledge of API versions or resources; callers
  # pass fully-qualified paths (e.g. "/api/v2/secret/conceal").
  class Transport
    IDEMPOTENT_METHODS = %i[get head].freeze
    RETRYABLE_STATUSES = [429, 500, 502, 503, 504].freeze
    RETRYABLE_ERRORS   = [
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
      Errno::ETIMEDOUT, EOFError, SocketError, IOError,
      Net::OpenTimeout, Net::ReadTimeout
    ].freeze

    METHOD_CLASSES = {
      get:    Net::HTTP::Get,
      post:   Net::HTTP::Post,
      patch:  Net::HTTP::Patch,
      put:    Net::HTTP::Put,
      delete: Net::HTTP::Delete,
      head:   Net::HTTP::Head,
    }.freeze

    def initialize(config)
      @config = config
    end

    # Execute an HTTP request.
    #
    # @param method [Symbol] :get, :post, :patch, ...
    # @param path [String] fully-qualified path including the /api/vN prefix
    # @param query [Hash, nil] query-string parameters
    # @param body [Hash, nil] request body serialized as JSON
    # @param form [Hash, nil] request body serialized as form-urlencoded
    # @param headers [Hash] extra request headers
    # @param raise_on_error [Boolean] raise APIError for status >= 400
    # @return [Onetime::Response]
    def request(method, path, query: nil, body: nil, form: nil, headers: {}, raise_on_error: true)
      uri = build_uri(path, query)
      attempt = 0

      begin
        response = perform(method, uri, body: body, form: form, headers: headers)

        if response.http_status >= 400
          if retryable_status?(response.http_status) && retry_allowed?(method, attempt)
            attempt += 1
            backoff(attempt)
            raise Retry
          end
          raise Errors.from_response(response) if raise_on_error
        end

        response
      rescue Retry
        retry
      rescue *RETRYABLE_ERRORS => e
        if retry_allowed?(method, attempt)
          attempt += 1
          backoff(attempt)
          retry
        end
        raise wrap_transport_error(e)
      end
    end

    # Encodes a Hash as application/x-www-form-urlencoded, expanding Array
    # values into repeated `key[]=` pairs (Rack's array convention, which
    # the v1 API relies on for `recipient`).
    def self.encode_form(hash)
      pairs = []
      hash.each do |key, value|
        next if value.nil?

        if value.is_a?(Array)
          value.each { |v| pairs << ["#{key}[]", v.to_s] }
        else
          pairs << [key.to_s, value.to_s]
        end
      end
      URI.encode_www_form(pairs)
    end

    private

    # Sentinel used to trigger a retry from within the begin/rescue.
    Retry = Class.new(StandardError)
    private_constant :Retry

    def perform(method, uri, body:, form:, headers:)
      request = build_request(method, uri, body: body, form: form, headers: headers)
      log(:debug) { "#{method.to_s.upcase} #{uri}" }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl     = uri.scheme == "https"
      http.open_timeout = @config.open_timeout
      http.read_timeout = @config.timeout

      raw = http.request(request)
      build_response(raw)
    end

    def build_request(method, uri, body:, form:, headers:)
      klass = METHOD_CLASSES.fetch(method) do
        raise ArgumentError, "Unsupported HTTP method: #{method.inspect}"
      end
      request = klass.new(uri)

      default_headers.merge(headers).each { |k, v| request[k] = v }

      unless @config.anonymous?
        # HTTP Basic: the customer extid occupies the username slot,
        # the API token occupies the password slot.
        request.basic_auth(@config.customer, @config.api_token)
      end

      if form
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = self.class.encode_form(form)
      elsif body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end

      request
    end

    def build_response(raw)
      status = raw.code.to_i
      raw_body = raw.body.to_s
      data = parse_body(raw, raw_body)

      Response.new(
        http_status: status,
        headers: raw.to_hash,
        raw_body: raw_body,
        data: data,
      )
    end

    def parse_body(raw, raw_body)
      return nil if raw_body.empty?

      content_type = raw["content-type"].to_s
      return raw_body unless content_type.include?("json")

      JSON.parse(raw_body)
    rescue JSON::ParserError
      # A non-JSON body on an otherwise-JSON endpoint: surface it raw rather
      # than blowing up, so callers can still inspect it.
      raw_body
    end

    def build_uri(path, query)
      uri = URI.join(ensure_trailing_slash(@config.base_url), path.sub(%r{\A/}, ""))
      if query && !query.empty?
        uri.query = self.class.encode_form(query)
      end
      uri
    end

    # URI.join treats the base as a directory only when it ends in "/".
    def ensure_trailing_slash(url)
      url.end_with?("/") ? url : "#{url}/"
    end

    def default_headers
      {
        "Accept"           => "application/json",
        "User-Agent"       => @config.user_agent || default_user_agent,
        "X-Onetime-Client" => "ruby:#{RUBY_VERSION}/#{Onetime::VERSION}",
      }.merge(@config.default_headers)
    end

    # Identifies the SDK, not the gem: "onetime-ruby" tells the service which
    # of the per-language clients is calling. The gem itself is `onetime`.
    def default_user_agent
      "onetime-ruby/#{Onetime::VERSION} (Ruby/#{RUBY_VERSION})"
    end

    def retry_allowed?(method, attempt)
      IDEMPOTENT_METHODS.include?(method) && attempt < @config.max_retries
    end

    def retryable_status?(status)
      RETRYABLE_STATUSES.include?(status)
    end

    # Exponential backoff: 0.5s, 1s, 2s, ...
    def backoff(attempt)
      sleep(0.5 * (2**(attempt - 1)))
    end

    def wrap_transport_error(error)
      if error.is_a?(Net::OpenTimeout) || error.is_a?(Net::ReadTimeout)
        TimeoutError.new("Request timed out: #{error.message}")
      else
        TransportError.new("Transport failure: #{error.message}")
      end
    end

    def log(level)
      return unless @config.logger

      @config.logger.public_send(level, "[onetime] #{yield}")
    end
  end
end
