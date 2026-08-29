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
require_relative "code_gen/validators/validator"
require_relative "code_gen/generators/generated_names"
require_relative "code_gen/generators/sink"
require_relative "code_gen/generators/json_sink"
require_relative "code_gen/generators/hash_sink"
require_relative "code_gen/generators/field_walk"
require_relative "code_gen/generators/record_access/generic"
require_relative "code_gen/generators/record_access/specialized"
require_relative "code_gen/generators/cycle_membership"
require_relative "code_gen/generators/descriptor_walk"
require_relative "code_gen/generators/field_index"
require_relative "code_gen/generators/release"
require_relative "code_gen/generators/banner"
require_relative "code_gen/generators/class_emitter"
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
  # Used by the +:wire_format+ JSON-column path emitted by
  # {Generators::JsonSink}.
  JSON_NOOP_PARSER = Object.new.freeze

  # Frozen options for the +:wire_format+ JSON-column validation
  # +Oj.sc_parse+ call. Passing +mode: :strict+ as a keyword argument
  # allocates a fresh Hash on every call into Oj's C entry point (one per
  # record); a hoisted frozen constant passed positionally reuses the same
  # object, so the per-record validation matches the old C extension's
  # allocation count. Emitted positionally by {Generators::JsonSink}'s
  # wire-format column path.
  JSON_STRICT_PARSE_OPTS = {mode: :strict}.freeze

  # Compiles +descriptor+ into a fresh Generated Class for the named
  # +output:+ mode. Thin facade — every call goes through the same
  # +Compiler+ orchestration so +Dump+ in S15 can plug in next to it
  # without retraining the internals.
  #
  # @param descriptor [Panko::CodeGen::Descriptor] the input
  # @param output [Symbol] +:json+ or +:hash+
  # @param config [Panko::CodeGen::Config] resolved settings;
  #   defaults to {Config.new} (library defaults)
  # @return [Class] a fresh Generated Class — two calls return two
  #   independent classes (Compile is a pure function).
  # @raise [Panko::CodeGen::CompileError] when semantic validation
  #   rejects the input
  # @raise [ArgumentError] when +output:+ is not in
  #   {Generator::OUTPUT_MODES}
  def self.compile(descriptor, output:, config: Config.new)
    Compiler.new(descriptor, output: output, config: config).compile
  end

  # Dumps +descriptor+ into a runnable +.rb+ file at +path:+ for the
  # named +output:+ mode. Thin facade — every call goes through the
  # same +Dump+ orchestration so the +Compile ≡ Dump byte-identical+
  # contract stays intact (the same +Generator+ output drives both
  # materialization paths). S15.2 ships flat single-file output;
  # nested-Descriptor multi-file fan-out is S15.5 territory.
  #
  # @param descriptor [Panko::CodeGen::Descriptor, Panko::Descriptor] the
  #   engine descriptor, or the public view (+MySerializer.descriptor+) —
  #   resolved back to the class's full engine descriptor. Runtime filters
  #   never change the generated source, so a filtered view dumps the same
  #   bytes as the unfiltered one.
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
    # The public view deliberately hides the engine descriptor, so resolve it
    # back through its serializer class — dumping shouldn't require reaching
    # into internals. defined?-guarded because the engine also loads
    # standalone, without Panko's public surface.
    if defined?(::Panko::Descriptor) && descriptor.is_a?(::Panko::Descriptor)
      descriptor = SerializerCache.descriptor_for(descriptor.serializer)
    end
    Dump.new(descriptor, output: output, config: config, path: path).dump
  end

  # Casts a Hash-mode attribute value to match Panko's C extension, whose Hash
  # mode pushed every leaf through +ObjectWriter#push_value+ — a blanket
  # +value.as_json+ (v0.8.5 lib/panko/object_writer.rb:33). So datetimes render
  # as their ISO-8601 String, Symbol/BigDecimal as Strings, Hash keys are
  # stringified, and arbitrary objects flatten through their own +#as_json+.
  # Emitted only into Hash-mode field writes; JSON mode leaves values raw
  # because Oj (+mode: :rails+) already applies the same conversions on write,
  # so wrapping there would double-format.
  #
  # The classes whose +#as_json+ is identity short-circuit on the first +when+
  # (NOT Symbol — +Symbol#as_json+ is its String) — this wrapper sits on every
  # Hash-mode field write, and the pass-through mix measured ~5x faster with
  # the early exit. Float gets its own branch because +Float#as_json+ is
  # +finite? ? self : nil+ — 0.8.5 emitted +nil+ for Infinity/NaN, and JSON
  # mode writes +null+ for them, so passing them through raw would diverge
  # both ways. The +respond_to?+ guard on the tail keeps the engine loadable
  # in bundles without ActiveSupport, where plain objects have no +#as_json+;
  # those pass through raw.
  def self.cast_datetime(value)
    case value
    when String, Integer, NilClass, TrueClass, FalseClass then value
    when Float then value.finite? ? value : nil
    else
      value.respond_to?(:as_json) ? value.as_json : value
    end
  end
end
