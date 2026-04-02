# frozen_string_literal: true

require_relative "support/benchmark"
require "panko_serializer"

benchmark("1 property, push_value") do
  writer = Panko::ObjectWriter.new
  writer.push_object
  writer.push_value "value1", "key1"
  writer.pop
  writer.output
end

benchmark("2 properties, push_value") do
  writer = Panko::ObjectWriter.new
  writer.push_object
  writer.push_value "value1", "key1"
  writer.push_value "value2", "key2"
  writer.pop
  writer.output
end

benchmark("1 property, push_key+push_value") do
  writer = Panko::ObjectWriter.new
  writer.push_object
  writer.push_key "key1"
  writer.push_value "value1"
  writer.pop
  writer.output
end

benchmark("2 properties, push_key+push_value") do
  writer = Panko::ObjectWriter.new
  writer.push_object
  writer.push_key "key1"
  writer.push_value "value1"
  writer.push_key "key2"
  writer.push_value "value2"
  writer.pop
  writer.output
end

benchmark("Nested object") do
  writer = Panko::ObjectWriter.new
  writer.push_object
  writer.push_value "value1", "key1"
  writer.push_object "key2"
  writer.push_value "value2", "key2"
  writer.pop
  writer.pop
  writer.output
end
