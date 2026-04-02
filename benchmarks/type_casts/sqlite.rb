# frozen_string_literal: true

require_relative "../support/benchmark"
require "active_record"
require "sqlite3"
require "panko_serializer"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

sqlite_int_type = ActiveRecord::Type::Integer.new(limit: 8)

benchmark("SQLite3 Integer(limit:8) TypeCast") do
  Panko._type_cast(sqlite_int_type, "42")
end

benchmark("SQLite3 Integer(limit:8) NoTypeCast") do
  Panko._type_cast(sqlite_int_type, 42)
end
