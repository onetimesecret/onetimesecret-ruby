# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name        = "onetime"
  spec.version     = "0.7.0"
  spec.authors     = ["Delano Mandelbaum"]
  spec.email       = ["gems@onetimesecret.com"]

  spec.summary     = "Compatibility package; use the onetimesecret gem"
  spec.description = "The onetime gem has moved to the canonical " \
                     "onetimesecret package."
  spec.homepage    = "https://github.com/onetimesecret/onetime-ruby"
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "source_code_uri"       => "https://github.com/onetimesecret/onetime-ruby",
    "bug_tracker_uri"       => "https://github.com/onetimesecret/onetime-ruby/issues",
    "documentation_uri"     => "https://docs.onetimesecret.com/",
    "changelog_uri"         => "https://github.com/onetimesecret/onetime-ruby/blob/main/CHANGES.txt",
    "rubygems_mfa_required" => "true",
  }

  spec.files = ["LICENSE.txt", "README.md"]

  spec.add_runtime_dependency "onetimesecret", "~> 0.7.0"
  spec.add_development_dependency "rake", "~> 13.0"

  spec.post_install_message = <<~MESSAGE

    The `onetime` gem has moved to `onetimesecret`.

    Update your Gemfile:

      gem "onetimesecret", "~> 0.7.0"

    The Ruby namespace remains `Onetime`, and `require "onetime"` remains
    supported by the canonical gem.

  MESSAGE
end
