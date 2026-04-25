# frozen_string_literal: true

module SerializersCodeGen
  # Sentinel a Method Attribute body returns to omit its Field from the
  # output. Identity-compared via +equal?+ at runtime so it never collides
  # with caller data; module-level + frozen so the identity is stable across
  # the program lifetime. Documented in +docs/descriptor.md § SKIP sentinel+.
  SKIP = Object.new.freeze

  # Internal namespace for structural-validation helpers shared by the
  # Descriptor-family +Data+ types. Helpers raise +DescriptorError+ with
  # messages following +docs/errors.md § Message convention+:
  # +"<Kind>#<Field>: <rule>; got <observed>:<ObservedClass>"+. The
  # parent +Descriptor+ wrapper (S1.4) prepends its +name+ when walking
  # its children; standalone construction omits it.
  module StructuralValidation
    module_function

    # Raises +DescriptorError+ when +value+ is not a +Symbol+, naming the
    # field-qualified location and the observed value + class.
    #
    # @param field [String] qualified name like +"Attribute#name"+
    # @param value [Object] the value to type-check
    # @return [void]
    # @raise [DescriptorError] when +value+ is not a +Symbol+
    def validate_symbol!(field, value)
      return if value.is_a?(Symbol)
      raise DescriptorError, "#{field}: must be a Symbol; got #{value.inspect}:#{value.class}"
    end

    # Raises +DescriptorError+ when +value+ is not a Callable — specifically
    # when it does not respond to +.call+ or is an +UnboundMethod+ (which
    # must be bound before inclusion, per +docs/descriptor.md § MethodAttribute+).
    #
    # @param field [String] qualified name like +"MethodAttribute#body"+
    # @param value [Object] the value to Callable-check
    # @return [void]
    # @raise [DescriptorError] when +value+ does not respond to +.call+ or
    #   is an +UnboundMethod+
    def validate_callable!(field, value)
      if value.is_a?(UnboundMethod)
        raise DescriptorError, "#{field}: must be a bound Callable, not an UnboundMethod; got #{value.inspect}:#{value.class}"
      end
      return if value.respond_to?(:call)
      raise DescriptorError, "#{field}: must respond to #call; got #{value.inspect}:#{value.class}"
    end
  end

  # A Field whose value is read directly from the Record via the Source
  # method. Both +name+ and +source+ are Symbols; +source+ defaults to
  # +name+ when omitted (per +docs/descriptor.md § Attribute+). Frozen on
  # construction; structural validation runs once at +.new+ and raises
  # +DescriptorError+ on shape violations.
  Attribute = Data.define(:name, :source) do
    # Validates +name+ and +source+ are Symbols, applying the
    # +source: name+ default when omitted.
    #
    # @param name [Symbol] output key
    # @param source [Symbol] method called on the Record; defaults to +name+
    # @return [void]
    # @raise [DescriptorError] when +name+ or +source+ is not a Symbol
    def initialize(name:, source: name)
      StructuralValidation.validate_symbol!("Attribute#name", name)
      StructuralValidation.validate_symbol!("Attribute#source", source)
      super
    end
  end

  # A Field whose value is computed by invoking a Callable with
  # +(record, context)+; the Callable may return +SKIP+ to omit the Field.
  # +body+ must respond to +.call+ and must not be an +UnboundMethod+ (must
  # be bound before inclusion, per +docs/descriptor.md § MethodAttribute+).
  # Arity validation is semantic and lands in S4 (+ArityError+); this slice
  # only enforces shape. Frozen on construction.
  MethodAttribute = Data.define(:name, :body) do
    # Validates +name+ is a Symbol and +body+ is a non-+UnboundMethod+
    # Callable.
    #
    # @param name [Symbol] output key
    # @param body [#call] the Callable invoked as +body.call(record, context)+
    # @return [void]
    # @raise [DescriptorError] when +name+ is not a Symbol, +body+ does not
    #   respond to +.call+, or +body+ is an +UnboundMethod+
    def initialize(name:, body:)
      StructuralValidation.validate_symbol!("MethodAttribute#name", name)
      StructuralValidation.validate_callable!("MethodAttribute#body", body)
      super
    end
  end
end
