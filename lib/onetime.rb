# frozen_string_literal: true

require_relative "onetime/version"
require_relative "onetime/errors"
require_relative "onetime/configuration"
require_relative "onetime/response"
require_relative "onetime/ownership"
require_relative "onetime/transport"
require_relative "onetime/client"

# Onetime is the official Ruby client for the OnetimeSecret API.
#
# It supports the v1 and v2 APIs over a zero-dependency, stdlib-only
# transport. See Onetime::Client for the primary interface.
#
#   require "onetime"
#
#   client = Onetime::Client.new(
#     base_url:    "https://us.onetimesecret.com",
#     customer:    "ur1abc23def",
#     api_token:   ENV["ONETIME_API_TOKEN"],
#     api_version: :v2,
#   )
#   res = client.secrets.conceal(secret: "hunter2", ttl: 3600)
#   res.dig("record", "secret", "secret_value")
module Onetime
  # Convenience constructor mirroring Onetime::Client.new.
  #
  #   Onetime.client(base_url: "https://us.onetimesecret.com",
  #                  customer: "ur1abc23def", api_token: "...")
  def self.client(**options)
    Client.new(**options)
  end
end
