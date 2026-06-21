# frozen_string_literal: true

module Onetime
  module Resources
    # Secret operations: conceal, generate, reveal, show, status.
    #
    # The request/response contracts differ between API versions:
    #   - v1 uses flat form-encoded params and legacy endpoint names
    #     (/share, /generate, POST /secret/:key for reveal).
    #   - v2 nests create params under a `secret` object, uses JSON bodies,
    #     and exposes richer REST endpoints (/secret/conceal, /secret/:id, ...).
    #
    # The version-specific branches are kept side by side in each method so
    # the differences are easy to audit.
    class Secrets
      def initialize(client)
        @client = client
      end

      # Conceal (share) a secret value you already have.
      #
      # @param secret [String] the secret content
      # @param ttl [Integer, nil] time-to-live in seconds
      # @param passphrase [String, nil] passphrase required to reveal
      # @param recipient [String, Array<String>, nil] email recipient(s)
      # @param share_domain [String, nil] custom share domain
      # @param guest [Boolean] use the anonymous /guest/* endpoint (v2)
      def conceal(secret:, ttl: nil, passphrase: nil, recipient: nil, share_domain: nil, guest: false)
        case version
        when :v1
          form = compact(secret: secret, ttl: ttl, passphrase: passphrase,
                         recipient: recipient, share_domain: share_domain)
          @client.request(:post, "/share", form: form)
        when :v2
          path = guest ? "/guest/secret/conceal" : "/secret/conceal"
          @client.request(:post, path, body: { secret: secret_payload(
            secret: secret, ttl: ttl, passphrase: passphrase,
            recipient: recipient, share_domain: share_domain
          ) })
        end
      end
      alias share conceal

      # Generate a random secret value server-side.
      def generate(ttl: nil, passphrase: nil, recipient: nil, share_domain: nil, guest: false)
        case version
        when :v1
          form = compact(ttl: ttl, passphrase: passphrase,
                         recipient: recipient, share_domain: share_domain)
          @client.request(:post, "/generate", form: form)
        when :v2
          path = guest ? "/guest/secret/generate" : "/secret/generate"
          @client.request(:post, path, body: { secret: secret_payload(
            ttl: ttl, passphrase: passphrase,
            recipient: recipient, share_domain: share_domain
          ) })
        end
      end

      # Reveal (consume) a secret by its key. This is a one-time action.
      #
      # @param key [String] the secret identifier
      # @param passphrase [String, nil] passphrase if one was set
      # @param continue [Boolean] confirm the destructive reveal
      def reveal(key, passphrase: nil, continue: true, guest: false)
        identifier = extract_secret_key(key)
        case version
        when :v1
          form = compact(passphrase: passphrase, continue: continue)
          @client.request(:post, "/secret/#{identifier}", form: form)
        when :v2
          path = guest ? "/guest/secret/#{identifier}/reveal" : "/secret/#{identifier}/reveal"
          @client.request(:post, path, body: compact(passphrase: passphrase, continue: continue))
        end
      end

      # Show a secret's metadata without revealing its value. (v2 only)
      def show(key, guest: false)
        require_version!(:v2, "secrets.show")
        identifier = extract_secret_key(key)
        path = guest ? "/guest/secret/#{identifier}" : "/secret/#{identifier}"
        @client.request(:get, path)
      end

      # Check a single secret's status. (v2 only)
      def status(key)
        require_version!(:v2, "secrets.status")
        @client.request(:get, "/secret/#{extract_secret_key(key)}/status")
      end

      # Check the status of multiple secrets in one call. (v2 only)
      #
      # @param keys [Array<String>, String] identifiers (array or CSV string)
      def status_list(keys)
        require_version!(:v2, "secrets.status_list")
        identifiers = keys.is_a?(Array) ? keys.join(",") : keys.to_s
        @client.request(:post, "/secret/status", body: { identifiers: identifiers })
      end

      private

      def version
        @client.api_version
      end

      # v2 create endpoints expect params nested under a `secret` object.
      def secret_payload(**attrs)
        compact(**attrs)
      end

      def compact(**attrs)
        attrs.reject { |_, v| v.nil? }
      end

      # Accept either a bare key or a full secret URL (e.g. the link a user
      # was given). Mirrors the convenience of the historical CLI.
      def extract_secret_key(key)
        str = key.to_s
        if (match = str.match(%r{/secret/([a-zA-Z0-9]+)}))
          match[1]
        else
          str
        end
      end

      def require_version!(expected, operation)
        return if version == expected

        raise UnsupportedOperationError,
              "#{operation} is only available on API #{expected}; client is configured for #{version}"
      end
    end
  end
end
