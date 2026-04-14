# frozen_string_literal: true

require_relative "code_gen/filter_mask"
require_relative "code_gen/value_capture"
require_relative "code_gen/generated_base"
require_relative "code_gen/active_record_attributes_writer"
require_relative "code_gen/emitter"
require_relative "code_gen/compiler"

module Panko
  # Code generation module for Panko serializers.
  #
  # Compiles per-serializer classes with unrolled attribute writes,
  # replacing the generic loop in +Engine::Serializer+ with inlined
  # per-attribute code for maximum throughput.
  #
  # Enabled by default.  Set +PANKO_CODE_GEN=0+ to disable.
  #
  # @example
  #   Panko::CodeGen.enabled?  # => true
  #   Panko::CodeGen.disable!
  #   Panko::CodeGen.enabled?  # => false
  module CodeGen
    @enabled = ENV["PANKO_CODE_GEN"] != "0"

    # Returns whether code generation is currently enabled.
    #
    # @return [Boolean]
    def self.enabled?
      @enabled
    end

    # Enables code generation.
    #
    # @return [void]
    def self.enable!
      @enabled = true
    end

    # Disables code generation.  New serializer classes will fall back
    # to the generic +Engine::Serializer+ loop.
    #
    # @return [void]
    def self.disable!
      @enabled = false
    end
  end
end
