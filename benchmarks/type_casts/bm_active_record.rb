# frozen_string_literal: true

require_relative "./support"

def ar_type_convert(type_klass, from, to)
  converter = type_klass.new

  if ENV["RAILS_VERSION"].start_with? "4.2"
    assert type_klass.name, converter.type_cast_from_database(from), to

    Benchmark.run("#{type_klass.name}_TypeCast") do
      converter.type_cast_from_database(from)
    end

    Benchmark.run("#{type_klass.name}_NoTypeCast") do
      converter.type_cast_from_database(to)
    end
  else
    assert type_klass.name, converter.deserialize(from), to

    Benchmark.run("#{type_klass.name}_TypeCast") do
      converter.deserialize(from)
    end

    Benchmark.run("#{type_klass.name}_NoTypeCast") do
      converter.deserialize(to)
    end
  end
end

def utc_ar_time
  date = DateTime.new(2017, 3, 4, 12, 45, 23)
  tz = ActiveSupport::TimeZone.new("UTC")
  from = date.in_time_zone(tz).iso8601

  type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::DateTime.new
  converter = ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter.new(type)

  if ENV["RAILS_VERSION"].start_with? "4.2"
    Benchmark.run("#{tz}_#{type.class.name}_TypeCast") do
      converter.type_cast_from_database(from).iso8601
    end
  else
    Benchmark.run("#{tz}_#{type.class.name}_TypeCast") do
      converter.deserialize(from).iso8601
    end
  end
end

def db_ar_time
  type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::DateTime.new
  converter = ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter.new(type)

  from = "2017-07-10 09:26:40.937392"

  if ENV["RAILS_VERSION"].start_with? "4.2"
    Benchmark.run("ActiveRecord_Time_TypeCast_WithISO8601") do
      converter.type_cast_from_database(from).iso8601
    end
  else
    Benchmark.run("ActiveRecord_Time_TypeCast_WithISO8601") do
      converter.deserialize(from).iso8601
    end
  end
end

ar_type_convert ActiveRecord::Type::String, 1, "1"
ar_type_convert ActiveRecord::Type::Text, 1, "1"
ar_type_convert ActiveRecord::Type::Integer, "1", 1
ar_type_convert ActiveRecord::Type::Float, "1.23", 1.23
ar_type_convert ActiveRecord::Type::Boolean, "true", true
ar_type_convert ActiveRecord::Type::Boolean, "t", true

if ENV["RAILS_VERSION"].start_with? "4.2"
  ar_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Integer, "1", 1
  ar_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Float, "1.23", 1.23
  ar_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Float, "Infinity", ::Float::INFINITY
end
if check_if_exists "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Json"
  ar_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Json, '{"a":1}', {a: 1}
end
if check_if_exists "ActiveRecord::Type::Json"
  ar_type_convert ActiveRecord::Type::Json, '{"a":1}', {a: 1}
end

db_ar_time
utc_ar_time
