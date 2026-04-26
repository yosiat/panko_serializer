# frozen_string_literal: true

# Loaded once per scenario invocation — each scenario file under benchmarks/
# runs as a fresh process (per docs/benchmarks.md § Running) so a single
# top-level `require_relative "support/setup"` chain is safe and idempotent in
# practice. Locks down the runtime environment for one bench run: gem load
# path, runtime gems, YJIT, AR connection.

require "active_record"
require "sqlite3"
require "oj"
require "benchmark/ips"
require "memory_profiler"

# StackProf is only loaded when PROFILE=cpu so default and PROFILE=memory runs
# don't pay the require cost (and so the harness loads on Rubies without the
# native extension built).
require "stackprof" if ENV["PROFILE"] == "cpu"

require "panko_serializer"

# oj_serializers/setup.rb auto-loads `rails` (via require "rails") unless
# `Oj.default_options[:use_raw_json]` is set beforehand. The bench suite uses
# AR (not full Rails); pre-setting the option dodges the rails require so we
# don't need a Rails dependency just to load the comparison target.
Oj.default_options = {mode: :rails, use_raw_json: true}

# oj_serializers calls `String#ends_with?` (an ActiveSupport alias for
# `end_with?`); without the core_ext it raises NoMethodError at the first
# attribute-emit codegen call.
require "active_support/core_ext/string/starts_ends_with"
require "oj_serializers"

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "serializers_code_gen"

# YJIT auto-enable per docs/phase-1-bar.md — phase-1 numbers are YJIT-on. No
# env knob to override; the production target is YJIT and we don't measure
# anything else.
RubyVM::YJIT.enable if defined?(RubyVM::YJIT)

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
