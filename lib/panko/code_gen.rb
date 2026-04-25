# frozen_string_literal: true

require_relative "serializers_code_gen/version"
require_relative "serializers_code_gen/errors"
require_relative "serializers_code_gen/descriptor"
require_relative "serializers_code_gen/code_builder"

# Internal Panko-ecosystem code generator. Turns an immutable Descriptor
# into a Generated Class that emits JSON or a Ruby Hash. Has no
# user-facing DSL — Panko owns that surface; this gem owns the input
# shape, the code-gen, and the runnable output.
module SerializersCodeGen
end
