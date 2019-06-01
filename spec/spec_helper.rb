# frozen_string_literal: true

require "bundler/setup"
require "panko_serializer"
require "faker"

require_relative "models"

RSpec.configure do |config|
  config.order = "random"

  # Enable flags like --only-failures and --next-failure
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

  config.before(:each) do
    FooHolder.delete_all
    FoosHolder.delete_all
    Foo.delete_all
  end
end

RSpec::Matchers.define :serialized_as do |serializer, output|
  match do |object|
    expect(serializer.serialize(object)).to eq(output)

    json = Oj.load serializer.serialize_to_json(object)
    expect(json).to eq(output)
  end

  failure_message do |object|
    <<~FAILURE

      Expected Output:
      #{output}

      Got:

      Object: #{serializer.serialize(object)}
      JSON: #{Oj.load(serializer.serialize_to_json(object))}
    FAILURE
  end
end
