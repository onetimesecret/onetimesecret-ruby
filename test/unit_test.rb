# frozen_string_literal: true

require_relative "test_helper"

class ConfigurationTest < Minitest::Test
  REGION = "https://us.onetimesecret.com"

  def test_defaults
    config = Onetime::Configuration.new
    assert_nil config.base_url, "there is no safe default base_url (data residency)"
    assert_equal :v2, config.api_version
    assert config.anonymous?
  end

  def test_organization_is_basic_auth_username
    config = Onetime::Configuration.new(organization: "on1abc", api_token: "tok")
    assert_equal "on1abc", config.organization
    assert_equal "on1abc", config.username, "username aliases organization"
    refute config.anonymous?
  end

  def test_username_is_accepted_as_alias_for_organization
    config = Onetime::Configuration.new(username: "on1abc", api_token: "tok")
    assert_equal "on1abc", config.organization
  end

  def test_normalizes_version_forms
    assert_equal :v1, Onetime::Configuration.new(api_version: 1).api_version
    assert_equal :v2, Onetime::Configuration.new(api_version: "v2").api_version
    assert_equal :v2, Onetime::Configuration.new(api_version: "2").api_version
  end

  def test_rejects_unsupported_version
    assert_raises(Onetime::ConfigurationError) do
      Onetime::Configuration.new(base_url: REGION, api_version: :v9).validate!
    end
  end

  def test_base_url_is_required
    err = assert_raises(Onetime::ConfigurationError) { Onetime::Configuration.new.validate! }
    assert_match(/base_url is required/, err.message)
  end

  def test_rejects_apex_domain_as_base_url
    %w[https://onetimesecret.com https://www.onetimesecret.com].each do |apex|
      err = assert_raises(Onetime::ConfigurationError) do
        Onetime::Configuration.new(base_url: apex).validate!
      end
      assert_match(/company website/, err.message)
    end
  end

  def test_accepts_regional_self_hosted_and_custom_domains
    %w[https://us.onetimesecret.com https://eu.onetimesecret.com
       https://secrets.mycompany.com http://localhost:3000].each do |url|
      assert Onetime::Configuration.new(base_url: url).validate!
    end
  end

  def test_rejects_invalid_base_url
    assert_raises(Onetime::ConfigurationError) do
      Onetime::Configuration.new(base_url: "not a url").validate!
    end
  end

  def test_rejects_partial_credentials
    assert_raises(Onetime::ConfigurationError) do
      Onetime::Configuration.new(base_url: REGION, organization: "on1abc").validate!
    end
    assert_raises(Onetime::ConfigurationError) do
      Onetime::Configuration.new(base_url: REGION, api_token: "tok").validate!
    end
  end

  def test_api_path_prefix
    assert_equal "/api/v1", Onetime::Configuration.new(api_version: :v1).api_path_prefix
  end
end

class ResponseTest < Minitest::Test
  def build(data, status: 200)
    Onetime::Response.new(http_status: status, headers: {}, raw_body: "", data: data)
  end

  def test_indifferent_access
    res = build({ "record" => { "secret" => { "secret_value" => "hi" } } })
    assert_equal "hi", res.dig(:record, :secret, :secret_value)
    assert_equal "hi", res.dig("record", "secret", "secret_value")
    assert_equal({ "secret_value" => "hi" }, res[:record]["secret"])
  end

  def test_success_and_code
    assert build(nil, status: 200).success?
    refute build(nil, status: 404).success?
    assert_equal 404, build(nil, status: 404).code
  end

  def test_dig_into_array
    res = build({ "records" => [{ "id" => 1 }] })
    assert_equal 1, res.dig("records", 0, "id")
  end
end

class ErrorsTest < Minitest::Test
  def from(status, data)
    res = Onetime::Response.new(http_status: status, headers: {}, raw_body: "", data: data)
    Onetime::Errors.from_response(res)
  end

  def test_maps_adr013_error_type
    err = from(404, { "error" => "No such secret", "error_type" => "RecordNotFound" })
    assert_instance_of Onetime::NotFoundError, err
    assert_equal "No such secret", err.message
    assert_equal "RecordNotFound", err.error_type
    assert_equal 404, err.http_status
  end

  def test_form_error_carries_field
    err = from(400, { "error" => "bad", "error_type" => "FormError", "field" => "secret" })
    assert_instance_of Onetime::BadRequestError, err
    assert_equal "secret", err.field
  end

  def test_rate_limit_carries_retry_after
    err = from(429, { "error" => "slow down", "error_type" => "LimitExceeded", "retry_after" => 30 })
    assert_instance_of Onetime::RateLimitError, err
    assert_equal 30, err.retry_after
  end

  def test_entitlement_error_is_forbidden_subclass
    err = from(403, { "error" => "upgrade", "error_type" => "EntitlementRequired", "entitlement" => "api_access" })
    assert_instance_of Onetime::EntitlementError, err
    assert_kind_of Onetime::ForbiddenError, err
    assert_equal "api_access", err.entitlement
  end

  def test_falls_back_to_status_when_no_error_type
    assert_instance_of Onetime::AuthenticationError, from(401, {})
    assert_instance_of Onetime::ServerError, from(503, {})
  end

  def test_legacy_v1_message_field
    err = from(404, { "message" => "Unknown secret" })
    assert_equal "Unknown secret", err.message
  end
end

class FormEncodingTest < Minitest::Test
  def test_expands_arrays_into_bracket_pairs
    encoded = Onetime::Transport.encode_form(recipient: ["a@b.com", "c@d.com"], ttl: 60)
    assert_includes encoded, "recipient%5B%5D=a%40b.com"
    assert_includes encoded, "recipient%5B%5D=c%40d.com"
    assert_includes encoded, "ttl=60"
  end

  def test_skips_nil_values
    encoded = Onetime::Transport.encode_form(a: nil, b: "x")
    refute_includes encoded, "a="
    assert_includes encoded, "b=x"
  end
end
