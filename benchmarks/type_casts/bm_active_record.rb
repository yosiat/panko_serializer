# frozen_string_literal: true

require_relative "support"

def ar_type_convert(type_klass, from, to)
  converter = type_klass.new

  assert type_klass.name, converter.deserialize(from), to

  Benchmark.run("#{type_klass.name}_TypeCast") do
    converter.deserialize(from)
  end

  Benchmark.run("#{type_klass.name}_NoTypeCast") do
    converter.deserialize(to)
  end
end

def utc_ar_time
  date = DateTime.new(2017, 3, 4, 12, 45, 23)
  tz = ActiveSupport::TimeZone.new("UTC")
  from = date.in_time_zone(tz).iso8601

  type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::DateTime.new
  converter = ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter.new(type)

  Benchmark.run("#{tz}_#{type.class.name}_TypeCast") do
    converter.deserialize(from).iso8601
  end
end

def db_ar_time
  type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::DateTime.new
  converter = ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter.new(type)

  from = "2017-07-10 09:26:40.937392"

  Benchmark.run("ActiveRecord_Time_TypeCast_WithISO8601") do
    converter.deserialize(from).iso8601
  end
end

ar_type_convert ActiveRecord::Type::String, 1, "1"
ar_type_convert ActiveRecord::Type::Text, 1, "1"
ar_type_convert ActiveRecord::Type::Integer, "1", 1
ar_type_convert ActiveRecord::Type::Float, "1.23", 1.23
ar_type_convert ActiveRecord::Type::Boolean, "true", true
ar_type_convert ActiveRecord::Type::Boolean, "t", true

if check_if_exists "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Json"
  ar_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Json, '{"a":1}', {a: 1}
end
if check_if_exists "ActiveRecord::Type::Json"
  ar_type_convert ActiveRecord::Type::Json, '{"a":1}', {a: 1}
end

db_ar_time
utc_ar_time
