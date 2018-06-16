# frozen_string_literal: true
require_relative "./support"

def panko_type_convert(type_klass, from, to)
  converter = type_klass.new
  assert "#{type_klass.name}", Panko::_type_cast(converter, from), to

  Benchmark.run("#{type_klass.name}_TypeCast") do
    Panko::_type_cast(converter, from)
  end

  Benchmark.run("#{type_klass.name}_NoTypeCast") do
    Panko::_type_cast(converter, to)
  end
end


def utc_panko_time
	date = DateTime.new(2017, 3, 4, 12, 45, 23)
	tz = ActiveSupport::TimeZone.new("UTC")
	from = date.in_time_zone(tz).iso8601

  type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::DateTime.new
  converter = ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter.new(type)

  to = Panko::_type_cast(converter, from)

  Benchmark.run("#{tz}_#{type.class.name}_TypeCast") do
    Panko::_type_cast(converter, from)
  end

  Benchmark.run("#{tz}_#{type.class.name}_NoTypeCast") do
    Panko::_type_cast(converter, to)
  end
end

def db_panko_time
  type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::DateTime.new
  converter = ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter.new(type)

  from = "2017-07-10 09:26:40.937392"

  Benchmark.run("Panko_Time_TypeCast") do
		Panko::_type_cast(converter, from)
  end
end

panko_type_convert ActiveRecord::Type::String, 1, "1"
panko_type_convert ActiveRecord::Type::Text, 1, "1"
panko_type_convert ActiveRecord::Type::Integer, "1", 1
panko_type_convert ActiveRecord::Type::Float, "1.23", 1.23
panko_type_convert ActiveRecord::Type::Boolean, "true", true
panko_type_convert ActiveRecord::Type::Boolean, "t", true

if ENV["RAILS_VERSION"].start_with? "4.2"
  panko_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Integer, "1", 1
  panko_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Float, "1.23", 1.23
  panko_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Float, "Infinity", ::Float::INFINITY
end

if check_if_exists "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Json"
  panko_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Json, '{"a":1}', {a:1}
end
if check_if_exists "ActiveRecord::Type::Json"
  panko_type_convert ActiveRecord::Type::Json, '{"a":1}', {a:1}
end
db_panko_time
utc_panko_time
