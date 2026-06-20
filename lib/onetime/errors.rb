# frozen_string_literal: true

module Onetime
  # Base class for every error raised by this library.
  class Error < StandardError; end

  # Raised when the client is misconfigured (bad base_url, missing
  # credentials for an authenticated call, unsupported api_version, ...).
  class ConfigurationError < Error; end

  # Raised when an operation is not available on the configured API
  # version (e.g. asking the v1 API for a secret's status).
  class UnsupportedOperationError < Error; end

  # Raised for transport-level failures: DNS, connection refused, reset
  # connections, TLS errors. Wraps the underlying exception in #cause.
  class TransportError < Error; end

  # Raised when a request exceeds the configured open/read timeout.
  class TimeoutError < TransportError; end

  # Base class for errors returned by the API (HTTP status >= 400).
  #
  # Carries the structured fields from the ADR-013 wire format
  # ({ error:, error_type:, ... }) as well as the legacy v1 { message: }
  # shape, so callers get a consistent interface across API versions.
  class APIError < Error
    attr_reader :http_status, :error_type, :code, :field, :error_key,
                :retry_after, :entitlement, :body, :response

    def initialize(message = nil, http_status: nil, error_type: nil, code: nil,
                   field: nil, error_key: nil, retry_after: nil, entitlement: nil,
                   body: nil, response: nil)
      super(message)
      @http_status = http_status
      @error_type  = error_type
      @code        = code
      @field       = field
      @error_key   = error_key
      @retry_after = retry_after
      @entitlement = entitlement
      @body        = body
      @response    = response
    end
  end

  class BadRequestError       < APIError; end # 400 / FormError
  class AuthenticationError   < APIError; end # 401
  class ForbiddenError        < APIError; end # 403 / Forbidden, GuestRoutesDisabled
  class EntitlementError      < ForbiddenError; end # EntitlementRequired
  class NotFoundError         < APIError; end # 404 / RecordNotFound
  class ConflictError         < APIError; end # 409
  class RateLimitError        < APIError; end # 429 / LimitExceeded
  class ServerError           < APIError; end # 5xx / ServerError

  # Builds the appropriate APIError subclass from an HTTP response.
  module Errors
    module_function

    # Maps the ADR-013 error_type (the machine-readable class name the
    # server sends) to a client exception class. Falls through to status
    # code mapping when the type is absent or unrecognized.
    ERROR_TYPE_MAP = {
      "FormError"           => BadRequestError,
      "RecordNotFound"      => NotFoundError,
      "NotFound"            => NotFoundError,
      "Forbidden"           => ForbiddenError,
      "GuestRoutesDisabled" => ForbiddenError,
      "EntitlementRequired" => EntitlementError,
      "LimitExceeded"       => RateLimitError,
      "ServerError"         => ServerError,
    }.freeze

    STATUS_MAP = {
      400 => BadRequestError,
      401 => AuthenticationError,
      403 => ForbiddenError,
      404 => NotFoundError,
      409 => ConflictError,
      422 => BadRequestError,
      429 => RateLimitError,
    }.freeze

    # @param response [Onetime::Response]
    # @return [Onetime::APIError]
    def from_response(response)
      body   = response.data.is_a?(Hash) ? response.data : {}
      status = response.http_status

      klass   = error_class(body["error_type"], status)
      message = body["error"] || body["message"] || default_message(status)

      klass.new(
        message,
        http_status: status,
        error_type:  body["error_type"],
        code:        body["code"],
        field:       body["field"],
        error_key:   body["error_key"],
        retry_after: body["retry_after"],
        entitlement: body["entitlement"],
        body:        response.data,
        response:    response,
      )
    end

    def error_class(error_type, status)
      ERROR_TYPE_MAP[error_type] ||
        STATUS_MAP[status] ||
        (status.to_i >= 500 ? ServerError : APIError)
    end

    def default_message(status)
      case status
      when 400 then "Bad request"
      when 401 then "Authentication failed"
      when 403 then "Forbidden"
      when 404 then "Not found"
      when 429 then "Rate limit exceeded"
      when 500..599 then "Server error (#{status})"
      else "Request failed (#{status})"
      end
    end
  end
end
