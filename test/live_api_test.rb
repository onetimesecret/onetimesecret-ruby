# frozen_string_literal: true

require_relative "test_helper"

# Live, real-API integration tests.
#
# These tests hit a real external OneTimeSecret deployment (the EU production
# host by default) and create real, ephemeral secrets. They are OPT-IN: unless
# ONETIME_LIVE=1 is set in the environment they are all skipped, so the default
# `rake test` run never touches the network.
#
#   ONETIME_LIVE=1 ruby -Ilib -Itest test/live_api_test.rb
#
# Configuration:
#   ONETIME_LIVE      -> set to any value to enable these tests
#   ONETIME_BASE_URL  -> override the target host (default: EU production)
#
# Only anonymous + guest/public endpoints are exercised (no credentials).
# Created secrets use a short TTL and clearly-marked test content, and
# assertions check structure and round-trip behaviour rather than exact
# server-supplied values (versions, identifiers, ...).
class LiveApiTest < Minitest::Test
  DEFAULT_BASE_URL = "https://ca.onetimesecret.com"
  TTL = 60

  def setup
    skip "set ONETIME_LIVE=1 to run live API tests" unless ENV["ONETIME_LIVE"]

    @base_url = ENV.fetch("ONETIME_BASE_URL", DEFAULT_BASE_URL)
    @client = Onetime::Client.new(base_url: @base_url, api_version: :v2)
  end

  # --- Public / meta endpoints -------------------------------------------

  def test_status_is_nominal
    res = @client.status

    assert_equal 200, res.http_status
    assert res.success?
    assert_equal "nominal", res["status"]
  end

  def test_version_is_present
    res = @client.version

    assert_equal 200, res.http_status
    assert res.success?
    # Don't hardcode the version numbers; just assert the field is present.
    assert res.key?("version"), "expected a 'version' key in the response body"
    refute_nil res["version"]
  end

  def test_supported_locales
    res = @client.supported_locales

    assert_equal 200, res.http_status
    assert res.success?
    # The exact shape of the locales payload is server-defined; just assert
    # the call succeeded and returned a non-empty body.
    refute_nil res.to_h
  end

  # --- Guest secret flows ------------------------------------------------

  def test_guest_conceal_reveal_round_trip
    value = unique_value("conceal-reveal")

    concealed = @client.secrets.conceal(secret: value, ttl: TTL, guest: true)
    assert_equal 200, concealed.http_status

    key = concealed.dig("record", "secret", "identifier")
    refute_nil key, "expected a secret identifier from conceal"

    revealed = @client.secrets.reveal(key, guest: true)
    assert_equal 200, revealed.http_status
    assert_equal value, revealed.dig("record", "secret_value")
  end

  def test_guest_generate_returns_receipt_and_secret
    res = @client.secrets.generate(ttl: TTL, guest: true)

    assert_equal 200, res.http_status
    assert res.success?
    refute_nil res.dig("record", "receipt"), "expected a receipt in the generated record"
    refute_nil res.dig("record", "secret"), "expected a secret in the generated record"
  end

  def test_guest_receipt_show
    value = unique_value("receipt-show")

    concealed = @client.secrets.conceal(secret: value, ttl: TTL, guest: true)
    assert_equal 200, concealed.http_status

    receipt_key = concealed.dig("record", "receipt", "identifier")
    refute_nil receipt_key, "expected a receipt identifier from conceal"

    res = @client.receipts.show(receipt_key, guest: true)
    assert_equal 200, res.http_status
    assert res.success?
  end

  # --- Error mapping -----------------------------------------------------

  def test_revealing_unknown_key_raises_api_error
    missing_key = "doesnotexist000000000000000000000"

    error = assert_raises(Onetime::APIError) do
      @client.secrets.reveal(missing_key, guest: true)
    end

    # Prefer the precise NotFoundError when the live service maps it that way,
    # but tolerate any 4xx mapped onto the APIError hierarchy.
    refute_nil error.http_status
    assert_operator error.http_status, :>=, 400
  end

  private

  # Clearly-marked, unique test content so created secrets are easy to spot
  # and never collide between runs.
  def unique_value(label)
    "onetime-ruby live test #{label} #{Time.now.to_i}-#{rand(1_000_000)}"
  end
end
