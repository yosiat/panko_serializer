# frozen_string_literal: true

require_relative "../support/benchmark"
require "active_record"
require "panko_serializer"

begin
  require "active_record/connection_adapters/mysql2_adapter"
rescue LoadError
  begin
    require "active_record/connection_adapters/trilogy_adapter"
  rescue LoadError
    puts "Skipping MySQL type_casts: mysql2/trilogy gem not installed"
    exit 0
  end
end

def bench_type(type_klass, from, to, label: type_klass.name)
  converter = type_klass.new

  benchmark("#{label} TypeCast") do
    Panko._type_cast(converter, from)
  end

  benchmark("#{label} NoTypeCast") do
    Panko._type_cast(converter, to)
  end
end

def bench_type_with_instance(instance, from, to, label:)
  benchmark("#{label} TypeCast") do
    Panko._type_cast(instance, from)
  end

  benchmark("#{label} NoTypeCast") do
    Panko._type_cast(instance, to)
  end
end

# --- MySQL-specific: UnsignedInteger ---

if defined?(ActiveRecord::Type::UnsignedInteger)
  bench_type ActiveRecord::Type::UnsignedInteger, "42", 42
end

# --- MySQL String with boolean coercion (true: "1", false: "0") ---

mysql_string = ActiveModel::Type::String.new(true: "1", false: "0") # rubocop:disable Lint/BooleanSymbol
bench_type_with_instance(mysql_string, 1, "1", label: "MySQL::String (bool coercion)")

mysql_immutable = ActiveModel::Type::ImmutableString.new(true: "1", false: "0") # rubocop:disable Lint/BooleanSymbol
bench_type_with_instance(mysql_immutable, 1, "1", label: "MySQL::ImmutableString (bool coercion)")

# --- MySQL Text size variants ---

bench_type_with_instance(ActiveRecord::Type::Text.new(limit: 2**8 - 1), 1, "1", label: "MySQL::TinyText")
bench_type_with_instance(ActiveRecord::Type::Text.new(limit: 2**16 - 1), 1, "1", label: "MySQL::Text")
bench_type_with_instance(ActiveRecord::Type::Text.new(limit: 2**24 - 1), 1, "1", label: "MySQL::MediumText")
bench_type_with_instance(ActiveRecord::Type::Text.new(limit: 2**32 - 1), 1, "1", label: "MySQL::LongText")

# --- MySQL Binary size variants ---

bench_type_with_instance(ActiveModel::Type::Binary.new(limit: 2**8 - 1), "data", "data".b, label: "MySQL::TinyBlob")
bench_type_with_instance(ActiveModel::Type::Binary.new(limit: 2**16 - 1), "data", "data".b, label: "MySQL::Blob")
bench_type_with_instance(ActiveModel::Type::Binary.new(limit: 2**24 - 1), "data", "data".b, label: "MySQL::MediumBlob")
bench_type_with_instance(ActiveModel::Type::Binary.new(limit: 2**32 - 1), "data", "data".b, label: "MySQL::LongBlob")

# --- MySQL Float variants ---

bench_type_with_instance(ActiveModel::Type::Float.new(limit: 24), "1.23", 1.23, label: "MySQL::Float (single)")
bench_type_with_instance(ActiveModel::Type::Float.new(limit: 53), "1.23", 1.23, label: "MySQL::Double (double)")

# --- MySQL Boolean (via tinyint(1) emulation) ---

bench_type_with_instance(ActiveModel::Type::Boolean.new, 1, true, label: "MySQL::Boolean (tinyint)")
