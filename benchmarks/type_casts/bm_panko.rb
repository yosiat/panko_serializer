# frozen_string_literal: true

require_relative "support"

class NoopWriter
  attr_reader :value
  def push_value(value, key)
    @value = value
    nil
  end

  def push_json(value, key)
    nil
  end
end

class Attribute
  attr_reader :name_for_serialization, :type

  def initialize(name_for_serialization:, type:)
    @name_for_serialization = name_for_serialization
    @type = type
  end
end

def panko_type_convert(type_klass, from, to)
  converter = type_klass.new

  writer = NoopWriter.new
  attribute = Attribute.new(name_for_serialization: "key", type: converter)

  Benchmark.run("#{type_klass.name}_TypeCast") do
    Panko::Impl::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, attribute, from)
  end

  Benchmark.run("#{type_klass.name}_NoTypeCast") do
    Panko::Impl::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, attribute, to)
  end
end

def utc_panko_time
  date = DateTime.new(2017, 3, 4, 12, 45, 23)
  tz = ActiveSupport::TimeZone.new("UTC")
  from = date.in_time_zone(tz).iso8601

  type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::DateTime.new
  converter = ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter.new(type)

  writer = NoopWriter.new
  attribute = Attribute.new(name_for_serialization: "key", type: converter)

  # get the to value
  Panko::Impl::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, attribute, from)
  to = writer.value

  Benchmark.run("#{tz}_#{type.class.name}_TypeCast") do
    Panko::Impl::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, attribute, from)
  end

  Benchmark.run("#{tz}_#{type.class.name}_NoTypeCast") do
    Panko::Impl::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, attribute, to)
  end
end

def db_panko_time
  type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::DateTime.new
  converter = ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter.new(type)

  from = "2017-07-10 09:26:40.937392"

  writer = NoopWriter.new
  attribute = Attribute.new(name_for_serialization: "key", type: converter)

  Benchmark.run("Panko_Time_TypeCast") do
    Panko::Impl::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, attribute, from)
  end
end

panko_type_convert ActiveRecord::Type::String, 1, "1"
panko_type_convert ActiveRecord::Type::Integer, "1", 1
panko_type_convert ActiveRecord::Type::Text, 1, "1"
panko_type_convert ActiveRecord::Type::Float, "1.23", 1.23
panko_type_convert ActiveRecord::Type::Boolean, "true", true
panko_type_convert ActiveRecord::Type::Boolean, "t", true

db_panko_time
utc_panko_time

if check_if_exists "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Json"
  panko_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Json, '{"a":1}', '{"a":1}'
end
if check_if_exists "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb"
  panko_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb, '{"a":1}', '{"a":1}'
end
if check_if_exists "ActiveRecord::Type::Json"
  panko_type_convert ActiveRecord::Type::Json, '{"a":1}', '{"a":1}'
end
