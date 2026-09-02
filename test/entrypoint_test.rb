# frozen_string_literal: true

require "open3"
require "rbconfig"
require_relative "test_helper"

class EntrypointTest < Minitest::Test
  def test_legacy_entrypoint_remains_loadable
    lib_dir = File.expand_path("../lib", __dir__)
    output, status = Open3.capture2e(
      RbConfig.ruby,
      "-I#{lib_dir}",
      "-ronetime",
      "-e",
      "print Onetime::VERSION"
    )

    assert status.success?, output
    assert_equal Onetime::VERSION, output
  end
end
