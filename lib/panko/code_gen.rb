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

# Internal code generator: turns an immutable Descriptor into a class that
# emits JSON or a Ruby Hash.
module Panko::CodeGen
  # Responds to no Oj callback, so +Oj.sc_parse+ only checks the JSON is valid
  # without building any Ruby objects.
  JSON_NOOP_PARSER = Object.new.freeze

  # Passed positionally: a +mode: :strict+ keyword would allocate a Hash per record.
  JSON_STRICT_PARSE_OPTS = {mode: :strict}.freeze

  # Returns a new Generated Class on every call. Raises CompileError when +descriptor+
  # cannot be compiled, ArgumentError when +output:+ is not +:json+ or +:hash+.
  def self.compile(descriptor, output:, config: Config.new)
    Compiler.new(descriptor, output: output, config: config).compile
  end

  # Writes one file per Descriptor (root at +path:+, children beside it) and returns
  # +path:+. Accepts a public +Panko::Descriptor+ too.
  def self.dump(descriptor, output:, path:, config: Config.new)
    # +defined?+ guard: the engine also loads standalone, without +Panko::Descriptor+.
    if defined?(::Panko::Descriptor) && descriptor.is_a?(::Panko::Descriptor)
      descriptor = SerializerCache.descriptor_for(descriptor.serializer)
    end
    Dump.new(descriptor, output: output, config: config, path: path).dump
  end

  # Hash mode only: converts a value the way Oj +:rails+ mode does in JSON mode (+#as_json+,
  # non-finite Float to nil). Without ActiveSupport there is no +#as_json+, so the value passes raw.
  def self.cast_datetime(value)
    # Runs on many Hash-mode field writes, so types whose +#as_json+ returns self skip the
    # call. Symbol is not one of them: its +#as_json+ is a String.
    case value
    when String, Integer, NilClass, TrueClass, FalseClass then value
    when Float then value.finite? ? value : nil
    else
      value.respond_to?(:as_json) ? value.as_json : value
    end
  end
end
