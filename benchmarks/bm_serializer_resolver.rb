# frozen_string_literal: true

require_relative "benchmarking_support"
require_relative "app"

class NotSerializer
end

class RealSerializer < Panko::Serializer
end

Benchmark.run("CantFindConst") do
  Panko::SerializerResolver.resolve("cant_find_const", Object)
end

Benchmark.run("NotSerializer") do
  Panko::SerializerResolver.resolve("not", Object)
end

Benchmark.run("RealSerializer") do
  Panko::SerializerResolver.resolve("real", Object)
end
