# frozen_string_literal: true

require_relative "test_helper"

# Onetime::Ownership decides whether a response describes a record the server
# recorded as anonymous. "Cannot tell" (nil) is a first-class answer.
class OwnershipTest < Minitest::Test
  def unowned?(data)
    Onetime::Ownership.unowned?(
      Onetime::Response.new(http_status: 200, headers: {}, raw_body: "", data: data)
    )
  end

  def test_anon_custid_is_unowned
    assert_equal true, unowned?({ "record" => { "custid" => "anon" } })
    assert_equal true, unowned?({ "record" => { "receipt" => { "custid" => "ANON" } } })
    assert_equal true, unowned?({ "custid" => "" })
  end

  def test_real_custid_is_owned
    assert_equal false, unowned?({ "record" => { "custid" => "on1abc23def" } })
    assert_equal false, unowned?({ "details" => { "owner" => "on1abc23def" } })
  end

  def test_anonymous_flags_including_v2_string_booleans
    assert_equal true, unowned?({ "record" => { "is_anonymous" => true } })
    assert_equal true, unowned?({ "record" => { "is_anonymous" => "true" } })
    assert_equal false, unowned?({ "record" => { "is_anonymous" => "false" } })
    assert_equal false, unowned?({ "record" => { "anonymous" => false } })
  end

  def test_unknown_shapes_return_nil
    assert_nil unowned?({ "record" => { "identifier" => "abc123" } })
    assert_nil unowned?({})
    assert_nil unowned?(nil)
    assert_nil unowned?("plain text body")
  end

  def test_any_anonymous_record_wins_over_an_owned_sibling
    data = { "record" => { "custid" => "on1abc23def", "secret" => { "custid" => "anon" } } }
    assert_equal true, unowned?(data)
  end
end

# Client behaviour when credentials were sent but the record came back
# anonymous (on_unowned: :warn by default, :raise, :ignore).
class ClientUnownedResponseTest < Minitest::Test
  include ClientTestHelpers

  ANON_BODY  = { "record" => { "custid" => "anon", "secret" => { "identifier" => "abc" } } }.freeze
  OWNED_BODY = { "record" => { "custid" => "on1example" } }.freeze

  # Captures logger.warn calls without pulling in a logging library.
  class WarnLogger
    attr_reader :warnings

    def initialize
      @warnings = []
    end

    def warn(message)
      @warnings << message
    end

    def debug(*); end
  end

  def build(data:, logger: WarnLogger.new, **opts)
    transport = FakeTransport.new(data: data)
    client = build_client(version: :v2, transport: transport, logger: logger, **opts)
    [client, logger]
  end

  def test_warns_once_when_credentials_were_sent_but_the_record_is_anonymous
    client, logger = build(data: ANON_BODY)

    client.secrets.conceal(secret: "hi")
    client.secrets.conceal(secret: "hi again")

    assert_equal 1, logger.warnings.size, "the warning should not repeat per request"
    assert_match(/recorded this secret as anonymous/, logger.warnings.first)
    assert_match(/organization extid/, logger.warnings.first)
  end

  # Clients are documented as shareable across threads, so the once-only
  # warning has to hold when several threads trip it at the same time.
  def test_warns_once_across_concurrent_requests
    client, logger = build(data: ANON_BODY)
    barrier = Queue.new

    threads = 12.times.map do
      Thread.new do
        barrier.pop
        client.secrets.conceal(secret: "hi")
      end
    end
    12.times { barrier << :go }
    threads.each(&:join)

    assert_equal 1, logger.warnings.size
  end

  def test_raises_when_configured_to
    client, = build(data: ANON_BODY, on_unowned: :raise)

    err = assert_raises(Onetime::UnownedResponseError) { client.secrets.conceal(secret: "hi") }
    assert_match(/anonymous/, err.message)
    assert_equal 200, err.response.http_status
  end

  def test_ignore_mode_is_silent
    client, logger = build(data: ANON_BODY, on_unowned: :ignore)

    assert client.secrets.conceal(secret: "hi")
    assert_empty logger.warnings
  end

  def test_owned_records_do_not_warn
    client, logger = build(data: OWNED_BODY, on_unowned: :raise)

    assert client.secrets.conceal(secret: "hi")
    assert_empty logger.warnings
  end

  def test_guest_routes_are_exempt
    client, logger = build(data: ANON_BODY, on_unowned: :raise)

    assert client.secrets.conceal(secret: "hi", guest: true)
    assert_empty logger.warnings
  end

  def test_anonymous_clients_are_exempt
    transport = FakeTransport.new(data: ANON_BODY)
    logger = WarnLogger.new
    client = Onetime::Client.new(
      base_url: "https://us.onetimesecret.com", transport: transport,
      logger: logger, on_unowned: :raise
    )

    assert client.secrets.conceal(secret: "hi")
    assert_empty logger.warnings
  end

  def test_warns_to_stderr_without_a_logger
    client, = build(data: ANON_BODY, logger: nil)

    captured = capture_io { client.secrets.conceal(secret: "hi") }
    assert_match(/\[onetime\].*anonymous/, captured.join)
  end

  def test_error_responses_are_not_ownership_checked
    transport = FakeTransport.new(status: 404, data: ANON_BODY)
    logger = WarnLogger.new
    client = build_client(version: :v2, transport: transport, logger: logger, on_unowned: :raise)

    assert client.secrets.show("abc"), "a 404 body is the transport's business, not ownership's"
    assert_empty logger.warnings
  end
end
