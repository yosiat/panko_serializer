require_relative './support'

def ar_type_convert(type_klass, from, to)
  converter = type_klass.new
  assert type_klass.name, converter.type_cast_from_database(from), to

  Benchmark.ams("#{type_klass.name}_TypeCast") do
    converter.type_cast_from_database(from)
  end

  Benchmark.ams("#{type_klass.name}_NoTypeCast") do
    converter.type_cast_from_database(to)
  end
end

def ar_time
  type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::DateTime.new
  converter = ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter.new(type)

  from = '2017-07-10 09:26:40.937392'
  to = converter.type_cast_from_database(from)

  Benchmark.ams("#{type.class.name}_TypeCast") do
    converter.type_cast_from_database(from)
  end

  Benchmark.ams("#{type.class.name}_NoTypeCast") do
    converter.type_cast_from_database(to)
  end
end

ar_type_convert ActiveRecord::Type::String, 1, '1'
ar_type_convert ActiveRecord::Type::Text, 1, '1'
ar_type_convert ActiveRecord::Type::Integer, '1', 1
ar_type_convert ActiveRecord::Type::Float, '1.23', 1.23
ar_type_convert ActiveRecord::Type::Float, 'Infinity', 0.0

ar_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Integer, '1', 1
ar_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Float, '1.23', 1.23
ar_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Float, 'Infinity', ::Float::INFINITY
ar_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Json, '{"a":1}', {a:1}
ar_time
