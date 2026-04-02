# frozen_string_literal: true

require_relative "../support/benchmark"
require "active_record"
require "panko_serializer"

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

bench_type ActiveRecord::Type::String, 1, "1"
bench_type ActiveRecord::Type::Text, 1, "1"
bench_type ActiveRecord::Type::ImmutableString, 1, "1"
bench_type ActiveRecord::Type::Integer, "1", 1
bench_type ActiveRecord::Type::BigInteger, "1", 1
bench_type ActiveRecord::Type::Float, "1.23", 1.23
bench_type ActiveRecord::Type::Decimal, "123.45", BigDecimal("123.45")
bench_type ActiveRecord::Type::Boolean, "true", true
bench_type ActiveRecord::Type::Boolean, "t", true, label: "ActiveRecord::Type::Boolean(t)"
bench_type ActiveRecord::Type::Date, "2017-03-04", Date.new(2017, 3, 4)
bench_type ActiveRecord::Type::Time, "2000-01-01 12:45:23", Time.utc(2000, 1, 1, 12, 45, 23)
bench_type ActiveRecord::Type::DateTime, "2017-03-04 12:45:23", Time.utc(2017, 3, 4, 12, 45, 23)
bench_type ActiveRecord::Type::Binary, "data", "data".b

if defined?(ActiveRecord::Type::Json)
  bench_type ActiveRecord::Type::Json, '{"a":1}', {"a" => 1}
end
