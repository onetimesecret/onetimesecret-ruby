# frozen_string_literal: true

module Onetime
  # Library version. Source of truth for the gemspec, the release workflow's
  # tag check, and the X-Onetime-Client / User-Agent request headers.
  #
  # Note for anyone comparing against RubyGems: 0.5.1 and earlier are the
  # unrelated 2013 command-line tool. This client starts at 1.0.0.
  VERSION = "1.0.0"
end
