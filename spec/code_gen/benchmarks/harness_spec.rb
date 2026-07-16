# frozen_string_literal: true

require "open3"
require "rspec"

# Smoke spec for the benchmark harness. Spawns each covered scenario as a
# subprocess (matching how `rake bench:all` runs scenarios) under a fast-
# iteration env so the suite stays under a few seconds per CI run, and asserts
# the stdout includes one row per target × size. Goal: catch "harness doesn't
# load", "scenario file syntax-errors", "missing requires", "broken target
# lookups", "missing oj_serializers dep" — not to validate numbers (per
# docs/ci.md § Benchmarks in CI, full benchmarks do not run in CI).
#
# Subprocess isolation matters: spec/spec_helper.rb has already established an
# AR connection and seeded the spec schema in this process. Running the bench
# harness in-process would re-establish the connection and trample the spec
# state — every subsequent example in the suite would fail. The bench harness
# is designed to be a fresh process anyway (per docs/benchmarks.md § Running),
# so the smoke spec exercises the production-shape path.
RSpec.describe "benchmark harness smoke" do
  let(:env) do
    {
      "IPS_TIME" => "0.02",
      "IPS_WARMUP" => "0.0",
      "SIZE" => "50"
    }
  end

  shared_examples "a bench scenario subprocess" do |scenario_file, scenario_label, expected_rows|
    let(:scenario_path) { File.expand_path("../../../benchmarks/#{scenario_file}", __dir__) }

    it "loads, runs, and emits one row per target at SIZE=50" do
      out, status = Open3.capture2e(env, "bundle", "exec", "ruby", scenario_path)
      expect(status).to be_success, "scenario subprocess failed:\n#{out}"
      expected_rows.each do |row|
        expect(out).to include("#{scenario_label} size=50/#{row}"), "missing row '#{row}' in subprocess stdout:\n#{out}"
      end
    end
  end

  describe "benchmarks/simple.rb" do
    include_examples "a bench scenario subprocess", "simple.rb", "Simple", [
      "code_gen/json",
      "code_gen/hash",
      "panko/json",
      "panko/object",
      "oj_serializers/json",
      "plain/json",
      "plain/hash"
    ]
  end
end
