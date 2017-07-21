require_relative './support'

def panko_type_convert(type_klass, from, to)
  converter = type_klass.new
  assert "#{type_klass.name}", Panko::_type_cast(converter, from), to

  Benchmark.ams("#{type_klass.name}_TypeCast") do
    Panko::_type_cast(converter, from)
  end

  Benchmark.ams("#{type_klass.name}_NoTypeCast") do
    Panko::_type_cast(converter, to)
  end
end

panko_type_convert ActiveRecord::Type::String, 1, '1'
panko_type_convert ActiveRecord::Type::Text, 1, '1'
panko_type_convert ActiveRecord::Type::Integer, '1', 1
panko_type_convert ActiveRecord::Type::Float, '1.23', 1.23
panko_type_convert ActiveRecord::Type::Float, 'Infinity', ::Float::INFINITY

panko_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Integer, '1', 1
panko_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Float, '1.23', 1.23
panko_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Float, 'Infinity', ::Float::INFINITY

panko_type_convert ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Json, '{"a":1}', {a:1}

