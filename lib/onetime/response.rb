# frozen_string_literal: true

module Onetime
  # A thin, indifferent-access wrapper around a parsed API response.
  #
  # The parsed JSON body is exposed via #[], #dig, #fetch and #to_h, all of
  # which accept either String or Symbol keys. The raw body string and HTTP
  # status are also available.
  #
  #   res = client.secrets.conceal(secret: "hi")
  #   res[:record][:receipt]["identifier"]
  #   res.dig("record", "secret", "secret_value")
  #   res.success?
  class Response
    attr_reader :http_status, :headers, :raw_body, :data

    def initialize(http_status:, headers:, raw_body:, data:)
      @http_status = http_status
      @headers     = headers || {}
      @raw_body    = raw_body
      @data        = data
    end

    # Indifferent key access. Returns nil for non-Hash bodies.
    def [](key)
      return nil unless data.is_a?(Hash)

      data[normalize(key)]
    end

    # Indifferent, deep access mirroring Hash#dig.
    def dig(*keys)
      keys.reduce(data) do |memo, key|
        case memo
        when Hash  then memo[normalize(key)]
        when Array then memo[key]
        end
      end
    end

    def fetch(key, *default, &block)
      raise TypeError, "response body is not a Hash" unless data.is_a?(Hash)

      data.fetch(normalize(key), *default, &block)
    end

    def key?(key)
      data.is_a?(Hash) && data.key?(normalize(key))
    end

    # 2xx status.
    def success?
      (200..299).cover?(http_status.to_i)
    end

    # Alias used by the legacy Onetime::API compatibility shim.
    def code
      http_status
    end

    def to_h
      data
    end

    private

    # Bodies are parsed with string keys; coerce symbol lookups to strings.
    def normalize(key)
      key.is_a?(Symbol) ? key.to_s : key
    end
  end
end
