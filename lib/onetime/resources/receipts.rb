# frozen_string_literal: true

module Onetime
  module Resources
    # Receipt operations (creator-facing secret metadata): show, recent,
    # burn, update.
    #
    # "Receipt" is the modern vocabulary; the v1 API also accepts the legacy
    # /private and /metadata aliases, but this client uses the canonical
    # /receipt paths that both versions support.
    class Receipts
      def initialize(client)
        @client = client
      end

      # Show a receipt by its key.
      def show(key, guest: false)
        identifier = key.to_s
        case version
        when :v1
          @client.request(:get, "/receipt/#{identifier}")
        when :v2
          path = guest ? "/guest/receipt/#{identifier}" : "/receipt/#{identifier}"
          @client.request(:get, path)
        end
      end

      # List the authenticated customer's recent receipts.
      def recent
        @client.request(:get, "/receipt/recent")
      end

      # Burn (destroy) an unread secret by its receipt key.
      def burn(key, passphrase: nil, continue: true, guest: false)
        identifier = key.to_s
        case version
        when :v1
          form = compact(passphrase: passphrase, continue: continue)
          @client.request(:post, "/receipt/#{identifier}/burn", form: form)
        when :v2
          path = guest ? "/guest/receipt/#{identifier}/burn" : "/receipt/#{identifier}/burn"
          @client.request(:post, path, body: compact(passphrase: passphrase, continue: continue))
        end
      end

      # Update a receipt's memo. (v2 only)
      def update(key, memo:)
        require_version!(:v2, "receipts.update")
        @client.request(:patch, "/receipt/#{key}", body: { memo: memo })
      end

      private

      def version
        @client.api_version
      end

      def compact(**attrs)
        attrs.reject { |_, v| v.nil? }
      end

      def require_version!(expected, operation)
        return if version == expected

        raise UnsupportedOperationError,
              "#{operation} is only available on API #{expected}; client is configured for #{version}"
      end
    end
  end
end
