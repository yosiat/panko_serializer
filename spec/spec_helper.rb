# frozen_string_literal: true

require "bundler/setup"
require "logger"
require "panko_serializer"
require "faker"
require "active_record"
require "temping"

require_relative "support/database_config"

require "sqlite3"

DatabaseConfig.setup_database
ActiveRecord::Base.establish_connection(DatabaseConfig.config)

ActiveRecord::Migration.verbose = false

RSpec.configure do |config|
  config.order = "random"

  config.example_status_persistence_file_path = ".rspec_status"

  config.filter_run focus: true
  config.run_all_when_everything_filtered = true

  config.full_backtrace = ENV.fetch("CI", false)

  if ENV.fetch("CI", false)
    config.before(:example, :focus) do
      raise "This example was committed with `:focus` and should not have been"
    end
  end

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.after do
    Temping.teardown
  end
end

RSpec::Matchers.define :serialized_as do |serializer_factory_or_class, output|
  serializer_factory = if serializer_factory_or_class.respond_to?(:call)
    serializer_factory_or_class
  else
    -> { serializer_factory_or_class.new }
  end

  match do |object|
    expect(serializer_factory.call.serialize(object)).to eq(output)

    json = Oj.load serializer_factory.call.serialize_to_json(object)
    expect(json).to eq(output)
  end

  failure_message do |object|
    <<~FAILURE

      Expected Output:
      #{output}

      Got:

      Object: #{serializer_factory.call.serialize(object)}
      JSON: #{Oj.load(serializer_factory.call.serialize_to_json(object))}
    FAILURE
  end
end

if GC.respond_to?(:verify_compaction_references)
  # Makes the GC move objects, to surface object-movement bugs.
  GC.verify_compaction_references(double_heap: true, toward: :empty)
end
