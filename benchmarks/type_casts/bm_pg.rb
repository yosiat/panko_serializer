# frozen_string_literal: true
require_relative "./support"

def pg_type_convert(type_klass, from, to)
  converter = type_klass.new
  assert type_klass.name, converter.decode(from), to

  Benchmark.ams("#{type_klass.name}_TypeCast") do
    converter.decode(from)
  end
end

def pg_time
  decoder = PG::TextDecoder::TimestampWithoutTimeZone.new

  from = "2017-07-10 09:26:40.937392"

  Benchmark.ams("#{decoder.class.name}_TypeCast") do
    decoder.decode(from)
  end

  Benchmark.ams("#{decoder.class.name}_TypeCast_InTimeZone") do
    decoder.decode(from).in_time_zone
  end
end




pg_type_convert PG::TextDecoder::Integer, "1", 1
pg_type_convert PG::TextDecoder::Float, "1.23", 1.23
pg_type_convert PG::TextDecoder::Float, "Infinity", ::Float::INFINITY
pg_type_convert PG::TextDecoder::Float, "-Infinity", ::Float::INFINITY
pg_type_convert PG::TextDecoder::Float, "NaN", ::Float::NaN
pg_time
