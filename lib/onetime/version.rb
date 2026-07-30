# frozen_string_literal: true

module Onetime
  # Library version. Source of truth for the gemspec, the release workflow's
  # tag check, and the X-Onetime-Client / User-Agent request headers.
  #
  # Note for anyone comparing against RubyGems: 0.5.1 (2013) and earlier are
  # the command-line tool that shipped under this gem name. 0.6.0 is the
  # cleaned-up client library.
  VERSION = "0.6.0"
end
