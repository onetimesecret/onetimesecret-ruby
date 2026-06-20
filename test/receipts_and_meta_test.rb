# frozen_string_literal: true

require_relative "test_helper"

class ReceiptsAndMetaTest < Minitest::Test
  include ClientTestHelpers

  def test_receipts_show_v1_and_v2_paths
    t1 = FakeTransport.new
    build_client(version: :v1, transport: t1).receipts.show("k1")
    assert_equal "/api/v1/receipt/k1", t1.last.path

    t2 = FakeTransport.new
    build_client(version: :v2, transport: t2).receipts.show("k2")
    assert_equal "/api/v2/receipt/k2", t2.last.path
  end

  def test_receipts_recent
    t = FakeTransport.new
    build_client(version: :v2, transport: t).receipts.recent
    assert_equal :get, t.last.method
    assert_equal "/api/v2/receipt/recent", t.last.path
  end

  def test_v1_burn_uses_form_v2_uses_json
    t1 = FakeTransport.new
    build_client(version: :v1, transport: t1).receipts.burn("k1")
    assert_equal "/api/v1/receipt/k1/burn", t1.last.path
    assert_equal({ continue: true }, t1.last.form)
    assert_nil t1.last.body

    t2 = FakeTransport.new
    build_client(version: :v2, transport: t2).receipts.burn("k2")
    assert_equal "/api/v2/receipt/k2/burn", t2.last.path
    assert_equal({ continue: true }, t2.last.body)
    assert_nil t2.last.form
  end

  def test_receipts_update_is_v2_only
    assert_raises(Onetime::UnsupportedOperationError) do
      build_client(version: :v1).receipts.update("k", memo: "note")
    end

    t = FakeTransport.new
    build_client(version: :v2, transport: t).receipts.update("k", memo: "note")
    assert_equal :patch, t.last.method
    assert_equal "/api/v2/receipt/k", t.last.path
    assert_equal({ memo: "note" }, t.last.body)
  end

  def test_meta_status_both_versions
    t = FakeTransport.new
    build_client(version: :v1, transport: t).status
    assert_equal "/api/v1/status", t.last.path
  end

  def test_version_and_locales_are_v2_only
    assert_raises(Onetime::UnsupportedOperationError) { build_client(version: :v1).version }
    assert_raises(Onetime::UnsupportedOperationError) { build_client(version: :v1).supported_locales }

    t = FakeTransport.new
    build_client(version: :v2, transport: t).version
    assert_equal "/api/v2/version", t.last.path
  end

  def test_authcheck_is_v1_only
    assert_raises(Onetime::UnsupportedOperationError) { build_client(version: :v2).authcheck }

    t = FakeTransport.new
    build_client(version: :v1, transport: t).authcheck
    assert_equal "/api/v1/authcheck", t.last.path
  end
end
