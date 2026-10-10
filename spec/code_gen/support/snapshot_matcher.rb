# frozen_string_literal: true

require "fileutils"
require "rspec/expectations"

module Panko::CodeGen
  module Spec
    SNAPSHOTS_DIR = File.expand_path("../fixtures/generated", __dir__)
  end
end

RSpec::Matchers.define :match_snapshot do |filename|
  match do |actual|
    @path = File.join(Panko::CodeGen::Spec::SNAPSHOTS_DIR, filename)
    @missing = !File.exist?(@path)
    @expected = File.read(@path) unless @missing
    update = ENV["UPDATE_SNAPSHOTS"]

    if !@missing && actual == @expected
      true
    elsif update == "1" || (update == "missing" && @missing)
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, actual)
      true
    else
      false
    end
  end

  failure_message do |actual|
    if @missing
      "snapshot not found: #{@path}\n" \
        "Run `rake snapshots:create_missing` to create it from the current Generator output."
    else
      diff = RSpec::Expectations.differ.diff(actual, @expected)
      "snapshot mismatch for #{File.basename(@path)}:#{diff}"
    end
  end
end
