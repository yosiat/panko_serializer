# frozen_string_literal: true

require "active_record"
require "sqlite3"

# In the merged Panko repo two files are named spec_helper.rb — Panko's at
# spec/spec_helper.rb and this one at spec/code_gen/spec_helper.rb. RSpec puts
# spec/ on the front of $LOAD_PATH, so a bare `require "spec_helper"` in a
# code_gen spec would otherwise resolve to Panko's (which re-establishes a fresh
# DB connection and clobbers this suite's in-memory schema). Prepending this
# directory makes `require "spec_helper"` resolve here — a no-op re-require —
# keeping the code_gen lane self-contained.
$LOAD_PATH.unshift __dir__
$LOAD_PATH.unshift File.expand_path("fixtures/generated", __dir__)
$LOAD_PATH.unshift File.expand_path("fixtures/descriptors", __dir__)

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

require "panko/code_gen"

require_relative "support/schema"
require_relative "support/models"
require_relative "support/base_serializer"
require_relative "support/snapshot_matcher"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = true
  config.default_formatter = "doc" if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed

  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
