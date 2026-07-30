# frozen_string_literal: true

module Onetime
  # Detects records the server recorded as *anonymous* (no owning account).
  #
  # This exists for one failure mode: a client configured with credentials
  # that the server does not honour. Older server versions answer such a
  # request with 200 and create the secret anonymously rather than rejecting
  # it, so the caller gets a working link that never appears in their account
  # and no error to explain why. Onetime::Client turns a positive detection
  # into a warning (or an exception with `on_unowned: :raise`).
  #
  # Detection is deliberately conservative: #unowned? returns nil — "cannot
  # tell" — unless the body carries a marker it recognizes, so an unfamiliar
  # response shape never produces a spurious warning.
  module Ownership
    module_function

    # Where ownership information lives across API versions and endpoints:
    # the v1 bodies are flat, v2 nests under record/details, and the record
    # itself may be the receipt or the secret.
    RECORD_PATHS = [
      [],
      %w[record],
      %w[record receipt],
      %w[record secret],
      %w[record metadata],
      %w[details],
    ].freeze

    # Keys naming the owning account.
    OWNER_KEYS = %w[
      custid customer_id owner owner_id organization organization_extid org_extid
    ].freeze

    # Owner values that mean "nobody". The service has used "anon" for
    # ownerless records since the v1 days.
    ANONYMOUS_OWNERS = ["", "anon", "anonymous", "guest", "null", "nil", "none"].freeze

    # Keys that state anonymity directly. v2 serializes booleans as strings,
    # hence the string handling in #truthy?.
    ANONYMOUS_FLAG_KEYS = %w[is_anonymous anonymous is_guest].freeze

    # @param response [Onetime::Response, Hash]
    # @return [Boolean, nil] true when a record is recorded as anonymous,
    #   false when a record names an owner, nil when neither can be determined
    def unowned?(response)
      data = response.respond_to?(:data) ? response.data : response
      return nil unless data.is_a?(Hash)

      # .compact, not .filter_map: `false` is a meaningful verdict here.
      verdicts = RECORD_PATHS.map { |path| dig_hash(data, path) }
                             .grep(Hash)
                             .map { |record| record_unowned?(record) }
                             .compact

      return true if verdicts.include?(true)

      verdicts.include?(false) ? false : nil
    end

    # @return [Boolean, nil] the verdict for a single record hash
    def record_unowned?(record)
      ANONYMOUS_FLAG_KEYS.each do |key|
        return truthy?(record[key]) if record.key?(key)
      end

      OWNER_KEYS.each do |key|
        next unless record.key?(key)

        return ANONYMOUS_OWNERS.include?(record[key].to_s.strip.downcase)
      end

      nil
    end

    def dig_hash(data, path)
      path.reduce(data) do |memo, key|
        memo.is_a?(Hash) ? memo[key] : nil
      end
    end

    def truthy?(value)
      case value
      when true then true
      when nil, false then false
      else %w[true 1 yes].include?(value.to_s.strip.downcase)
      end
    end
  end
end
