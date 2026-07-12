# frozen_string_literal: true

require "oj"

require_relative "code_gen/version"
require_relative "code_gen/errors"
require_relative "code_gen/config"
require_relative "code_gen/descriptor"
require_relative "code_gen/code_builder"
require_relative "code_gen/filter"
require_relative "code_gen/datetime_format"
require_relative "code_gen/active_record/access_classifier"
require_relative "code_gen/active_record/define_attribute_methods"
require_relative "code_gen/validators/callable_arity"
require_relative "code_gen/validators/source_resolution"
require_relative "code_gen/validators/name_uniqueness"
require_relative "code_gen/validators/symbol_body_dispatch"
require_relative "code_gen/validators/validator"
require_relative "code_gen/generators/field_emitters/attribute"
require_relative "code_gen/generators/field_emitters/method_attribute"
require_relative "code_gen/generators/field_emitters/association"
require_relative "code_gen/generators/record_access/generic"
require_relative "code_gen/generators/record_access/specialized"
require_relative "code_gen/generators/cycle_membership"
require_relative "code_gen/generators/descriptor_walk"
require_relative "code_gen/generators/field_index"
require_relative "code_gen/generators/release"
require_relative "code_gen/generators/banner"
require_relative "code_gen/generators/json_mode"
require_relative "code_gen/generators/hash_mode"
require_relative "code_gen/generators/fanout"
require_relative "code_gen/generator"
require_relative "code_gen/compile_cache"
require_relative "code_gen/compiler"
require_relative "code_gen/dump"
require_relative "code_gen/writers_pool"

# Internal Panko-ecosystem code generator. Turns an immutable Descriptor
# into a Generated Class that emits JSON or a Ruby Hash. Has no
# user-facing DSL — Panko owns that surface; this gem owns the input
# shape, the code-gen, and the runnable output.
module Panko::CodeGen
  # Frozen no-op handler for +Oj.sc_parse+. The handler is queried via
  # +respond_to?+ for +hash_start+ / +array_start+ / +add_value+ / etc.;
  # an +Object.new+ instance responds to none of them, so Oj's C path
  # skips every callback and validates well-formedness without
  # materializing the parsed structure or invoking any Ruby callback.
  # Used by the +:wire_format+ JSON-column emit path emitted by
  # {Generators::FieldEmitters::Attribute.emit_json_column}; see
  # {file:docs/code_gen/config.md} for rationale and benchmark numbers.
  JSON_NOOP_PARSER = Object.new.freeze

  # Frozen options for the +:wire_format+ JSON-column validation
  # +Oj.sc_parse+ call. Passing +mode: :strict+ as a keyword argument
  # allocates a fresh Hash on every call into Oj's C entry point (one per
  # record); a hoisted frozen constant passed positionally reuses the same
  # object, so the per-record validation matches the old C extension's
  # allocation count. Emitted positionally by
  # {Generators::FieldEmitters::Attribute.emit_json_column}.
  JSON_STRICT_PARSE_OPTS = {mode: :strict}.freeze

  # Compiles +descriptor+ into a fresh Generated Class for the named
  # +output:+ mode. Thin facade per +docs/code_gen/structure.md § Public API
  # surface+ — every call goes through the same +Compiler+ orchestration
  # so +Dump+ in S15 can plug in next to it without retraining the
  # internals.
  #
  # @param descriptor [Panko::CodeGen::Descriptor] the input
  # @param output [Symbol] +:json+ or +:hash+
  # @param config [Panko::CodeGen::Config] resolved settings;
  #   defaults to {Config.new} (library defaults)
  # @return [Class] a fresh Generated Class — two calls return two
  #   independent classes (Compile is a pure function per
  #   +docs/code_gen/compilation.md+).
  # @raise [Panko::CodeGen::CompileError] when semantic validation
  #   rejects the input
  # @raise [ArgumentError] when +output:+ is not in
  #   {Generator::OUTPUT_MODES}
  def self.compile(descriptor, output:, config: Config.new)
    Compiler.new(descriptor, output: output, config: config).compile
  end

  # Dumps +descriptor+ into a runnable +.rb+ file at +path:+ for the
  # named +output:+ mode. Thin facade per +docs/code_gen/structure.md § Public
  # API surface+ — every call goes through the same +Dump+
  # orchestration so the +Compile ≡ Dump byte-identical+ contract from
  # +docs/code_gen/structure.md § Layered architecture+ stays intact (the same
  # +Generator+ output drives both materialization paths). S15.2 ships
  # flat single-file output; nested-Descriptor multi-file fan-out is
  # S15.5 territory.
  #
  # @param descriptor [Panko::CodeGen::Descriptor] the input
  # @param output [Symbol] +:json+ or +:hash+
  # @param config [Panko::CodeGen::Config] resolved settings;
  #   defaults to {Config.new} (library defaults)
  # @param path [String] on-disk target file path; required, must be a
  #   non-empty +String+ — anything else raises +ArgumentError+ before
  #   any disk side effect
  # @return [String] the +path:+ argument the bytes were written to
  # @raise [Panko::CodeGen::CompileError] when semantic validation
  #   rejects the input
  # @raise [ArgumentError] when +output:+ is not in
  #   {Generator::OUTPUT_MODES}, or when +path:+ is +nil+, empty, or
  #   not a String
  def self.dump(descriptor, output:, path:, config: Config.new)
    Dump.new(descriptor, output: output, config: config, path: path).dump
  end

  # Casts a Hash-mode attribute value to match Panko's C extension: datetime
  # types render as their ISO-8601 String (+#as_json+ — millisecond precision,
  # offset preserved, UTC as +Z+), everything else passes through untouched.
  # Emitted only into Hash-mode field writes; JSON mode leaves values raw
  # because Oj (+mode: :rails+) already formats these types identically on
  # write, so wrapping there would double-format. Only the datetime classes are
  # converted — a blanket +#as_json+ would also stringify Symbol/BigDecimal and
  # change Hash mode's raw pass-through for them.
  #
  # The common non-datetime classes short-circuit on the first +when+ —
  # this wrapper sits on every Hash-mode field write, and the pass-through
  # mix measured ~5x faster with the early exit than with the datetime
  # checks (and their per-call +defined?+) running first. +TimeWithZone+
  # stays +defined?+-guarded on the rare tail so the engine remains
  # loadable (and load-order-proof) in bundles without ActiveSupport.
  def self.cast_datetime(value)
    case value
    when String, Integer, NilClass, Float, Symbol, TrueClass, FalseClass then value
    when Time, Date then value.as_json
    else
      (defined?(ActiveSupport::TimeWithZone) && value.is_a?(ActiveSupport::TimeWithZone)) ? value.as_json : value
    end
  end
end
