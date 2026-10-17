# frozen_string_literal: true

require "open3"
require "rspec"

# Checks that each scenario loads and prints one row per target; it does not check the numbers.
# Runs in a subprocess because the harness would replace this process's AR connection and schema.
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
