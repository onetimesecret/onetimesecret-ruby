# frozen_string_literal: true

require_relative "test_helper"

# Exercises the retry/backoff logic of Onetime::Transport in isolation.
#
# The private #perform and #backoff/#sleep methods are overridden per-instance
# with singleton methods so no real network call or sleep ever happens; this
# keeps the suite deterministic and sub-second while still driving the real
# #request control flow (retry policy, status mapping, error wrapping).
class TransportRetryTest < Minitest::Test
  # Builds a Response without touching the network.
  def resp(status, data = {})
    Onetime::Response.new(http_status: status, headers: {}, raw_body: "", data: data)
  end

  # Builds a transport whose #perform yields a programmed sequence and whose
  # #sleep is captured rather than executed. Returns [transport, state] where
  # state exposes the recorded sleeps and the perform call count.
  def build_transport(responses, max_retries: 2)
    cfg = Onetime::Configuration.new(
      base_url: "https://eu.onetimesecret.com", max_retries: max_retries
    )
    t = Onetime::Transport.new(cfg)

    state = Struct.new(:sleeps, :perform_calls).new([], 0)
    queue = responses.dup

    # Never actually sleep; just record the requested backoff duration.
    t.define_singleton_method(:sleep) { |secs| state.sleeps << secs }

    # Pop the next programmed result; raise it if it's an exception.
    t.define_singleton_method(:perform) do |*_args, **_kw|
      state.perform_calls += 1
      result = queue.shift
      result.is_a?(Exception) ? (raise result) : result
    end

    [t, state]
  end

  def test_get_retries_on_503_then_succeeds_on_second_attempt
    t, state = build_transport([resp(503), resp(200)])

    response = t.request(:get, "/api/v2/status")

    assert_equal 200, response.http_status
    assert_equal 2, state.perform_calls
  end

  def test_get_raises_server_error_after_exhausting_retries_on_503
    t, state = build_transport([resp(503), resp(503), resp(503)])

    assert_raises(Onetime::ServerError) { t.request(:get, "/api/v2/status") }
    # 1 initial attempt + 2 retries (max_retries: 2).
    assert_equal 3, state.perform_calls
  end

  def test_post_is_not_retried_on_503
    t, state = build_transport([resp(503)])

    assert_raises(Onetime::ServerError) do
      t.request(:post, "/api/v2/secret/conceal", body: { secret: "hi" })
    end
    # POST is not idempotent, so no retry happens.
    assert_equal 1, state.perform_calls
  end

  def test_get_retries_on_connection_reset_then_succeeds
    t, state = build_transport([Errno::ECONNRESET.new, resp(200)])

    response = t.request(:get, "/api/v2/status")

    assert_equal 200, response.http_status
    assert_equal 2, state.perform_calls
  end

  def test_get_raises_transport_error_after_exhausting_retries_on_network_error
    t, state = build_transport(
      [Errno::ECONNRESET.new, Errno::ECONNRESET.new, Errno::ECONNRESET.new]
    )

    assert_raises(Onetime::TransportError) { t.request(:get, "/api/v2/status") }
    assert_equal 3, state.perform_calls
  end

  def test_backoff_durations_are_exponential
    t, state = build_transport([resp(503), resp(503), resp(200)])

    response = t.request(:get, "/api/v2/status")

    assert_equal 200, response.http_status
    # backoff(attempt): 0.5 * 2**(attempt-1) -> attempt 1 => 0.5, attempt 2 => 1.0
    assert_equal [0.5, 1.0], state.sleeps
  end

  def test_max_retries_zero_disables_retries
    t, state = build_transport([resp(503)], max_retries: 0)

    assert_raises(Onetime::ServerError) { t.request(:get, "/api/v2/status") }
    assert_equal 1, state.perform_calls
    assert_empty state.sleeps
  end

  def test_raise_on_error_false_returns_response_after_exhausting_retries
    t, state = build_transport([resp(503), resp(503), resp(503)])

    response = t.request(:get, "/api/v2/status", raise_on_error: false)

    assert_equal 503, response.http_status
    assert_equal 3, state.perform_calls
  end
end
