# frozen_string_literal: true

require "active_record"
require "sqlite3"
require "oj"
require "benchmark/ips"
require "memory_profiler"

# Loaded only for PROFILE=cpu, so other runs do not load the profiler.
require "stackprof" if ENV["PROFILE"] == "cpu"

require "panko_serializer"

# Setting use_raw_json before loading oj_serializers stops it from requiring rails.
Oj.default_options = {mode: :rails, use_raw_json: true}

# oj_serializers calls String#ends_with?, which only this ActiveSupport extension defines.
require "active_support/core_ext/string/starts_ends_with"
require "oj_serializers"

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "panko/code_gen"

# Always on: the benchmarks only measure YJIT.
RubyVM::YJIT.enable if defined?(RubyVM::YJIT)

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
