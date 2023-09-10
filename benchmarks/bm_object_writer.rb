# frozen_string_literal: true

require_relative "benchmarking_support"
require_relative "app"

Benchmark.run("ObjectWriter_OneProperty_PushValue") do
  writer = Panko::ObjectWriter.new

  writer.push_object
  writer.push_value "value1", "key1"
  writer.pop

  writer.output
end

Benchmark.run("ObjectWriter_TwoProperty_PushValue") do
  writer = Panko::ObjectWriter.new

  writer.push_object
  writer.push_value "value1", "key1"
  writer.push_value "value2", "key2"
  writer.pop

  writer.output
end

Benchmark.run("ObjectWriter_OneProperty_PushValuePushKey") do
  writer = Panko::ObjectWriter.new

  writer.push_object
  writer.push_key "key1"
  writer.push_value "value1"
  writer.pop

  writer.output
end

Benchmark.run("ObjectWriter_TwoProperty_PushValuePushKey") do
  writer = Panko::ObjectWriter.new

  writer.push_object
  writer.push_key "key1"
  writer.push_value "value1"

  writer.push_key "key2"
  writer.push_value "value2"
  writer.pop

  writer.output
end

Benchmark.run("ObjectWriter_NestedObject") do
  writer = Panko::ObjectWriter.new

  writer.push_object
  writer.push_value "value1", "key1"

  writer.push_object "key2"
  writer.push_value "value2", "key2"
  writer.pop

  writer.pop

  writer.output
end
