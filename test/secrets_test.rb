# frozen_string_literal: true

require_relative "test_helper"

class SecretsTest < Minitest::Test
  include ClientTestHelpers

  # --- v1: flat form params, legacy endpoints -----------------------------

  def test_v1_conceal_posts_flat_form_to_share
    t = FakeTransport.new
    build_client(version: :v1, transport: t).secrets.conceal(
      secret: "hi", ttl: 3600, passphrase: "pw", recipient: "a@b.com"
    )

    call = t.last
    assert_equal :post, call.method
    assert_equal "/api/v1/share", call.path
    assert_nil call.body, "v1 must not send a JSON body"
    assert_equal({ secret: "hi", ttl: 3600, passphrase: "pw", recipient: "a@b.com" }, call.form)
  end

  def test_v1_generate_posts_to_generate
    t = FakeTransport.new
    build_client(version: :v1, transport: t).secrets.generate(ttl: 60)

    assert_equal "/api/v1/generate", t.last.path
    assert_equal({ ttl: 60 }, t.last.form)
  end

  def test_v1_reveal_posts_form_to_secret_key
    t = FakeTransport.new
    build_client(version: :v1, transport: t).secrets.reveal("abc123", passphrase: "pw")

    assert_equal :post, t.last.method
    assert_equal "/api/v1/secret/abc123", t.last.path
    assert_equal({ passphrase: "pw", continue: true }, t.last.form)
  end

  def test_v1_show_is_unsupported
    client = build_client(version: :v1)
    assert_raises(Onetime::UnsupportedOperationError) { client.secrets.show("abc") }
  end

  # --- v2: nested JSON payloads, REST endpoints ---------------------------

  def test_v2_conceal_nests_payload_under_secret_as_json
    t = FakeTransport.new
    build_client(version: :v2, transport: t).secrets.conceal(
      secret: "hi", ttl: 3600, recipient: ["a@b.com"]
    )

    call = t.last
    assert_equal :post, call.method
    assert_equal "/api/v2/secret/conceal", call.path
    assert_nil call.form, "v2 must not send a form body"
    assert_equal({ secret: { secret: "hi", ttl: 3600, recipient: ["a@b.com"] } }, call.body)
  end

  def test_v2_conceal_omits_nil_params
    t = FakeTransport.new
    build_client(version: :v2, transport: t).secrets.conceal(secret: "hi")

    assert_equal({ secret: { secret: "hi" } }, t.last.body)
  end

  def test_v2_guest_conceal_uses_guest_path
    t = FakeTransport.new
    build_client(version: :v2, transport: t).secrets.conceal(secret: "hi", guest: true)

    assert_equal "/api/v2/guest/secret/conceal", t.last.path
  end

  def test_v2_reveal_posts_json_to_reveal_endpoint
    t = FakeTransport.new
    build_client(version: :v2, transport: t).secrets.reveal("abc123", passphrase: "pw")

    assert_equal "/api/v2/secret/abc123/reveal", t.last.path
    assert_equal({ passphrase: "pw", continue: true }, t.last.body)
  end

  def test_v2_reveal_accepts_full_secret_url
    t = FakeTransport.new
    url = "https://onetimesecret.com/secret/abc123def"
    build_client(version: :v2, transport: t).secrets.reveal(url)

    assert_equal "/api/v2/secret/abc123def/reveal", t.last.path
  end

  def test_v2_show_gets_secret
    t = FakeTransport.new
    build_client(version: :v2, transport: t).secrets.show("abc123")

    assert_equal :get, t.last.method
    assert_equal "/api/v2/secret/abc123", t.last.path
  end

  def test_v2_status_list_joins_array_into_csv
    t = FakeTransport.new
    build_client(version: :v2, transport: t).secrets.status_list(%w[a b c])

    assert_equal "/api/v2/secret/status", t.last.path
    assert_equal({ identifiers: "a,b,c" }, t.last.body)
  end
end
