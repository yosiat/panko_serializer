# frozen_string_literal: true

require "oj"

require_relative "serializers_code_gen/version"
require_relative "serializers_code_gen/errors"
require_relative "serializers_code_gen/config"
require_relative "serializers_code_gen/descriptor"
require_relative "serializers_code_gen/code_builder"
require_relative "serializers_code_gen/validators/callable_arity"
require_relative "serializers_code_gen/validators/validator"
require_relative "serializers_code_gen/generators/field_emitters/attribute"
require_relative "serializers_code_gen/generators/field_emitters/association"
require_relative "serializers_code_gen/generators/record_access/generic"
require_relative "serializers_code_gen/generators/descriptor_walk"
require_relative "serializers_code_gen/generators/json_mode"
require_relative "serializers_code_gen/generators/hash_mode"
require_relative "serializers_code_gen/generator"
require_relative "serializers_code_gen/compile_cache"
require_relative "serializers_code_gen/compiler"

# Internal Panko-ecosystem code generator. Turns an immutable Descriptor
# into a Generated Class that emits JSON or a Ruby Hash. Has no
# user-facing DSL — Panko owns that surface; this gem owns the input
# shape, the code-gen, and the runnable output.
module SerializersCodeGen
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
end
