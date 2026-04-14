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
  # Compiles per-serializer classes with unrolled attribute writes —
  # inlined per-attribute code for maximum throughput.
  module CodeGen
  end
end
