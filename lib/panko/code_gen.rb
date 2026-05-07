# frozen_string_literal: true

require "oj"

require_relative "serializers_code_gen/version"
require_relative "serializers_code_gen/errors"
require_relative "serializers_code_gen/config"
require_relative "serializers_code_gen/descriptor"
require_relative "serializers_code_gen/code_builder"
require_relative "serializers_code_gen/filter"
require_relative "serializers_code_gen/active_record/access_classifier"
require_relative "serializers_code_gen/active_record/define_attribute_methods"
require_relative "serializers_code_gen/validators/callable_arity"
require_relative "serializers_code_gen/validators/source_resolution"
require_relative "serializers_code_gen/validators/name_uniqueness"
require_relative "serializers_code_gen/validators/validator"
require_relative "serializers_code_gen/generators/field_emitters/attribute"
require_relative "serializers_code_gen/generators/field_emitters/method_attribute"
require_relative "serializers_code_gen/generators/field_emitters/association"
require_relative "serializers_code_gen/generators/record_access/generic"
require_relative "serializers_code_gen/generators/record_access/specialized"
require_relative "serializers_code_gen/generators/cycle_membership"
require_relative "serializers_code_gen/generators/descriptor_walk"
require_relative "serializers_code_gen/generators/field_index"
require_relative "serializers_code_gen/generators/banner"
require_relative "serializers_code_gen/generators/json_mode"
require_relative "serializers_code_gen/generators/hash_mode"
require_relative "serializers_code_gen/generator"
require_relative "serializers_code_gen/compile_cache"
require_relative "serializers_code_gen/compiler"
require_relative "serializers_code_gen/dump"
require_relative "serializers_code_gen/writers_pool"

# Internal Panko-ecosystem code generator. Turns an immutable Descriptor
# into a Generated Class that emits JSON or a Ruby Hash. Has no
# user-facing DSL — Panko owns that surface; this gem owns the input
# shape, the code-gen, and the runnable output.
module SerializersCodeGen
  # Frozen no-op handler for +Oj.sc_parse+. The handler is queried via
  # +respond_to?+ for +hash_start+ / +array_start+ / +add_value+ / etc.;
  # an +Object.new+ instance responds to none of them, so Oj's C path
  # skips every callback and validates well-formedness without
  # materializing the parsed structure or invoking any Ruby callback.
  # Used by the +:wire_format+ JSON-column emit path emitted by
  # {Generators::FieldEmitters::Attribute.emit_json_column}; see
  # {file:docs/config.md} for rationale and benchmark numbers.
  JSON_NOOP_PARSER = Object.new.freeze

  # Compiles +descriptor+ into a fresh Generated Class for the named
  # +output:+ mode. Thin facade per +docs/structure.md § Public API
  # surface+ — every call goes through the same +Compiler+ orchestration
  # so +Dump+ in S15 can plug in next to it without retraining the
  # internals.
  #
  # @param descriptor [SerializersCodeGen::Descriptor] the input
  # @param output [Symbol] +:json+ or +:hash+
  # @param config [SerializersCodeGen::Config] resolved settings;
  #   defaults to {Config.new} (library defaults)
  # @return [Class] a fresh Generated Class — two calls return two
  #   independent classes (Compile is a pure function per
  #   +docs/compilation.md+).
  # @raise [SerializersCodeGen::CompileError] when semantic validation
  #   rejects the input
  # @raise [ArgumentError] when +output:+ is not in
  #   {Generator::OUTPUT_MODES}
  def self.compile(descriptor, output:, config: Config.new)
    Compiler.new(descriptor, output: output, config: config).compile
  end

  # Dumps +descriptor+ into a runnable +.rb+ file at +path:+ for the
  # named +output:+ mode. Thin facade per +docs/structure.md § Public
  # API surface+ — every call goes through the same +Dump+
  # orchestration so the +Compile ≡ Dump byte-identical+ contract from
  # +docs/structure.md § Layered architecture+ stays intact (the same
  # +Generator+ output drives both materialization paths). S15.2 ships
  # flat single-file output; nested-Descriptor multi-file fan-out is
  # S15.5 territory.
  #
  # @param descriptor [SerializersCodeGen::Descriptor] the input
  # @param output [Symbol] +:json+ or +:hash+
  # @param config [SerializersCodeGen::Config] resolved settings;
  #   defaults to {Config.new} (library defaults)
  # @param path [String] on-disk target file path; required, must be a
  #   non-empty +String+ — anything else raises +ArgumentError+ before
  #   any disk side effect
  # @return [String] the +path:+ argument the bytes were written to
  # @raise [SerializersCodeGen::CompileError] when semantic validation
  #   rejects the input
  # @raise [ArgumentError] when +output:+ is not in
  #   {Generator::OUTPUT_MODES}, or when +path:+ is +nil+, empty, or
  #   not a String
  def self.dump(descriptor, output:, path:, config: Config.new)
    Dump.new(descriptor, output: output, config: config, path: path).dump
  end
end
