# frozen_string_literal: true

require_relative "../support/benchmark"
require "active_record"
require "sqlite3"
require "panko_serializer"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

VW = Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter

class TypeAttribute
  attr_reader :name_for_serialization, :type
  attr_accessor :cached_writer

  def initialize(name:, type:)
    @name_for_serialization = name
    @type = type
    @cached_writer = nil
  end
end

sqlite_int_type = ActiveRecord::Type::Integer.new(limit: 8)
writer = NoopWriter.new
attribute = TypeAttribute.new(name: "key", type: sqlite_int_type)

benchmark("SQLite3 Integer(limit:8) TypeCast") do
  VW.write(writer, attribute, "42")
end

benchmark("SQLite3 Integer(limit:8) NoTypeCast") do
  VW.write(writer, attribute, 42)
end
