# frozen_string_literal: true

module Panko::CodeGen
  # Errors raised by user code (method bodies, record reads) are not wrapped in it.
  class Error < StandardError; end

  # Raised while building a Descriptor or one of its parts with a wrong type or shape,
  # and by Config for an invalid +hash_*_key_type+.
  class DescriptorError < Error; end

  class CompileError < Error; end

  class NameCollisionError < CompileError; end

  # Specialized path only: the source is neither a column nor a method on the model.
  # On the generic path a missing method raises Ruby's own +NoMethodError+ at run time.
  class UnknownSourceError < CompileError; end

  # A method body or +if:+ callable whose arity is outside 0..3, variadic included.
  class ArityError < CompileError; end
end
