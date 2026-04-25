# frozen_string_literal: true

module SerializersCodeGen
  # Root of the library exception hierarchy. All errors raised by
  # +serializers-code-gen+ inherit from this class — callers may rescue
  # +SerializersCodeGen::Error+ as a catch-all or rescue the specific
  # subclass they care about. Ruby built-ins originating from user code
  # (Callable bodies, Record access) are not wrapped; see
  # +docs/errors.md § What's not in the hierarchy+.
  class Error < StandardError; end

  # Raised at +Data.new+ when a Descriptor (or one of its child Data
  # types — Attribute, MethodAttribute, Association, Config) is built
  # with the wrong type or shape. Detected by structural validation,
  # which runs once per construction.
  class DescriptorError < Error; end

  # Raised at +Compile+ time when the Generator walks a structurally
  # valid Descriptor and finds a semantic problem no +Data.new+ check
  # could catch. Runs once per Compile call, before any source is
  # emitted. Specific failure modes are signalled by the subclasses
  # below.
  class CompileError < Error; end

  # Raised when two Fields at the same level share a +name+. Since
  # every Field contributes exactly one output key, a duplicate name
  # makes the emitted output ambiguous.
  class NameCollisionError < CompileError; end

  # Raised on the specialized path when an Attribute's +source+ is
  # neither a column on every Model nor an instance method on every
  # Model (per the 3-step classification rule in
  # +docs/compilation.md+). Generic-path Descriptors (+Models: nil+)
  # never raise this — missing methods surface at runtime as Ruby's
  # own +NoMethodError+.
  class UnknownSourceError < CompileError; end

  # Raised when a Callable (MethodAttribute +body+ or Association
  # +if:+) has an arity outside +{0, 1, 2}+. Variadic Callables
  # (+arity == -1+, +-2+) also raise. The allowed arities are pinned
  # in +docs/descriptor.md § Callable arity+.
  class ArityError < CompileError; end
end
