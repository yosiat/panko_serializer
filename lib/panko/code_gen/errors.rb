# frozen_string_literal: true

module Panko::CodeGen
  # Root of the library exception hierarchy. All errors raised by
  # +serializers-code-gen+ inherit from this class — callers may rescue
  # +Panko::CodeGen::Error+ as a catch-all or rescue the specific
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
  # +if:+) has an arity outside +{0, 1, 2, 3}+. Variadic Callables
  # (any negative arity — +-1+, +-2+, +-3+, ...) also raise. The
  # allowed arities are pinned in +docs/descriptor.md § Callable
  # arity+.
  class ArityError < CompileError; end

  # Raised when a +MethodAttribute+ has a +Symbol+ +body+ but its
  # owning +Descriptor+ has +parent_class: nil+. Symbol-body Method
  # Attributes dispatch via +value = <method_name>+ on +self+ — the
  # Generated Class must subclass a user-supplied +parent_class+ for
  # the method to resolve. +MethodAttribute.new+ has no view of the
  # owning Descriptor's +parent_class+, so this legitimacy check
  # cannot live in structural validation; +Validators::SymbolBodyDispatch+
  # walks the Descriptor tree at +Compile+ time and raises this error
  # before any source is emitted.
  class SymbolBodyError < CompileError; end
end
