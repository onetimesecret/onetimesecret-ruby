# frozen_string_literal: true

require_relative "lib/onetime/version"

Gem::Specification.new do |spec|
  spec.name        = "onetime"
  spec.version     = Onetime::VERSION
  spec.authors     = ["Delano Mandelbaum"]
  spec.email       = ["delano@onetimesecret.com"]

  spec.summary     = "Official Ruby client for the OnetimeSecret API"
  spec.description = "A modern, dependency-free Ruby client for the OnetimeSecret " \
                     "API, supporting the v1 and v2 API versions."
  spec.homepage    = "https://github.com/onetimesecret/onetime-ruby"
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "source_code_uri"       => "https://github.com/onetimesecret/onetime-ruby",
    "bug_tracker_uri"       => "https://github.com/onetimesecret/onetime-ruby/issues",
    "documentation_uri"     => "https://docs.onetimesecret.com/",
    "changelog_uri"         => "https://github.com/onetimesecret/onetime-ruby/blob/master/CHANGES.txt",
    "rubygems_mfa_required" => "true",
  }

  spec.files = Dir[
    "lib/**/*.rb",
    "LICENSE.txt",
    "README.md",
    "CHANGES.txt",
  ]
  spec.require_paths = ["lib"]

  # Zero runtime dependencies: the client is built entirely on the Ruby
  # standard library (net/http, uri, json) so it drops cleanly into any
  # environment without pulling transitive gems. The CLI lives in a
  # separate `onetime-cli` gem.

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
