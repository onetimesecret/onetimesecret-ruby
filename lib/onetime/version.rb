# frozen_string_literal: true

module Onetime
  # Library version. Source of truth for the gemspec, the release workflow's
  # tag check, and the X-Onetime-Client / User-Agent request headers.
  #
  # The client was published as `onetime` through 0.6.0. Starting with 0.7.0,
  # the canonical RubyGems package is `onetimesecret`; the Ruby namespace and
  # load paths remain unchanged.
  VERSION = "0.7.0"
end
