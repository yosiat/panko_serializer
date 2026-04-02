# frozen_string_literal: true

require_relative "../support/benchmark"
require "active_record"
require "panko_serializer"

begin
  require "pg"
  require "active_record/connection_adapters/postgresql_adapter"
rescue LoadError
  puts "Skipping PostgreSQL type_casts: pg gem not installed"
  exit 0
end

Time.zone = "UTC"

def bench_type(type_klass, from, to, label: type_klass.name)
  converter = type_klass.new

  benchmark("#{label} TypeCast") do
    Panko._type_cast(converter, from)
  end

  benchmark("#{label} NoTypeCast") do
    Panko._type_cast(converter, to)
  end
end

PG_OID = ActiveRecord::ConnectionAdapters::PostgreSQL::OID

bench_type PG_OID::Uuid, "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11", "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"

if defined?(PG_OID::Jsonb)
  bench_type PG_OID::Jsonb, '{"a":1}', {"a" => 1}
end

if defined?(PG_OID::Hstore)
  bench_type PG_OID::Hstore, '"a"=>"1"', {"a" => "1"}
end

if defined?(PG_OID::Inet)
  bench_type PG_OID::Inet, "192.168.1.1", IPAddr.new("192.168.1.1")
end

if defined?(PG_OID::Cidr)
  bench_type PG_OID::Cidr, "192.168.1.0/24", IPAddr.new("192.168.1.0/24")
end

if defined?(PG_OID::Macaddr)
  bench_type PG_OID::Macaddr, "00:11:22:33:44:55", "00:11:22:33:44:55"
end

if defined?(PG_OID::Point)
  bench_type PG_OID::Point, "(1.0,2.0)", [1.0, 2.0]
end

if defined?(PG_OID::Money)
  bench_type PG_OID::Money, "$1,234.56", BigDecimal("1234.56")
end

if defined?(PG_OID::Bit)
  bench_type PG_OID::Bit, "101", "101"
end

if defined?(PG_OID::BitVarying)
  bench_type PG_OID::BitVarying, "101", "101"
end

if defined?(PG_OID::Xml)
  bench_type PG_OID::Xml, "<a/>", "<a/>"
end

if defined?(PG_OID::Enum)
  bench_type PG_OID::Enum, "active", "active"
end

if defined?(PG_OID::DateTime)
  tz_type = PG_OID::DateTime.new
  tz_converter = ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter.new(tz_type)

  benchmark("PG DateTime+TZ TypeCast") do
    Panko._type_cast(tz_converter, "2017-07-10 09:26:40.937392")
  end
end
