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
  # +"<Kind>#<Field>: <rule>; got <observed>:<ObservedClass>"+. Each
  # +Data+ type validates its own fields at +.new+; +Descriptor+ does not
  # re-walk its children's interiors (they have already validated
  # themselves), only the array-element types of its three Field-kind
  # arrays.
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

    # Raises +DescriptorError+ when +value+ is not a non-empty +String+. Used
    # for +Descriptor#name+, which becomes the Generated Class identifier and
    # the synthetic-backtrace path stem — empty / nil names would silently
    # produce malformed code-gen output downstream.
    #
    # @param field [String] qualified name like +"Descriptor#name"+
    # @param value [Object] the value to type-check
    # @return [void]
    # @raise [DescriptorError] when +value+ is not a +String+ or is empty
    def validate_non_empty_string!(field, value)
      return if value.is_a?(String) && !value.empty?
      raise DescriptorError, "#{field}: must be a non-empty String; got #{value.inspect}:#{value.class}"
    end

    # Raises +DescriptorError+ when +value+ is neither +nil+ nor an +Array+
    # of +Class+ objects. Encodes the +Models+ contract from
    # +docs/descriptor.md § Descriptor#models+: +nil+ unlocks the generic
    # path, +Array<Class>+ unlocks compile-time specialization.
    #
    # @param field [String] qualified name; expected to be +"Descriptor#models"+
    # @param value [Array<Class>, nil] the value to type-check
    # @return [void]
    # @raise [DescriptorError] when +value+ is non-nil and not an
    #   +Array<Class>+
    def validate_models!(field, value)
      return if value.nil?
      unless value.is_a?(Array) && value.all?(Class)
        raise DescriptorError, "#{field}: must be nil or Array<Class>; got #{value.inspect}:#{value.class}"
      end
    end

    # Raises +DescriptorError+ when +value+ is not an +Array+ whose elements
    # all +is_a?+ +element_class+. Used for the per-Field-kind arrays on
    # +Descriptor+ (+attributes+, +method_attributes+, +associations+).
    # Reports the first offending element verbatim so the message points at
    # exactly which slot failed.
    #
    # @param field [String] qualified name like +"Descriptor#attributes"+
    # @param value [Array] the value to type-check
    # @param element_class [Class] the required element type (e.g. +Attribute+)
    # @param kind_label [String] human-readable element-kind name used in the
    #   message (e.g. +"Attribute"+) — kept distinct from +element_class.name+
    #   so the namespace prefix doesn't leak into user-facing messages
    # @return [void]
    # @raise [DescriptorError] when +value+ is not an +Array+ or contains an
    #   element that is not an instance of +element_class+
    def validate_array_of!(field, value, element_class, kind_label)
      unless value.is_a?(Array)
        raise DescriptorError, "#{field}: must be an Array of #{kind_label}; got #{value.inspect}:#{value.class}"
      end
      bad = value.find { |el| !el.is_a?(element_class) }
      return if bad.nil?
      raise DescriptorError, "#{field}: must contain only #{kind_label} elements; got #{bad.inspect}:#{bad.class}"
    end

    # Raises +DescriptorError+ when +value+ is not a +Descriptor+ instance.
    # Used for +Association#descriptor+ — the type identity that
    # nested-recursion handling in S5/S8 keys off via +.equal?+.
    #
    # @param field [String] qualified name like +"Association#descriptor"+
    # @param value [Object] the value to type-check
    # @return [void]
    # @raise [DescriptorError] when +value+ is not a +Descriptor+
    def validate_descriptor!(field, value)
      return if value.is_a?(Descriptor)
      raise DescriptorError, "#{field}: must be a Descriptor; got #{value.inspect}:#{value.class}"
    end

    # Raises +DescriptorError+ when +value+ is not in the
    # +Association+ Kind enum +{:has_one, :has_many}+. The discriminator that
    # selects the +Association+'s emit path (single object vs collection).
    #
    # @param field [String] qualified name; expected to be +"Association#kind"+
    # @param value [Object] the value to enum-check
    # @return [void]
    # @raise [DescriptorError] when +value+ is not +:has_one+ or +:has_many+
    def validate_kind!(field, value)
      return if Association::KINDS.include?(value)
      raise DescriptorError, "#{field}: must be :has_one or :has_many; got #{value.inspect}:#{value.class}"
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

  # A Field linking one Descriptor to another — the data shape of a
  # has_one / has_many edge between two Records (per
  # +docs/descriptor.md § Association+). The +descriptor+ field may
  # reference the parent itself for self-recursive shapes (Comment with
  # +has_many :replies+ pointing back at Comment); the recursive emit /
  # construction handling lands later in S5 + S8. Frozen on construction.
  #
  # Field defaults applied at +.new+ time:
  #
  # - +source+: defaults to +name+ if omitted or passed as +nil+ — matches
  #   +docs/descriptor.md § Association+ ("output key matches the model
  #   method" common case).
  # - +if+: defaults to +nil+ — no guard, no runtime cost.
  Association = Data.define(:name, :kind, :descriptor, :source, :if) do
    # Validates +name+ is a Symbol, +kind+ is in +{:has_one, :has_many}+,
    # +descriptor+ is a +Descriptor+ instance, +source+ is a Symbol
    # (defaulting to +name+ when omitted or passed as +nil+), and +if+ is
    # +nil+ or a non-+UnboundMethod+ Callable.
    #
    # @param name [Symbol] output key
    # @param kind [Symbol] +:has_one+ or +:has_many+
    # @param descriptor [Descriptor] the nested Descriptor — may be the
    #   parent itself for self-recursion
    # @param source [Symbol, nil] method on the parent Record returning the
    #   related Record(s); nil/omitted falls back to +name+
    # @param if [Proc, Method, nil] optional guard Callable invoked as
    #   +if.call(record, context)+; nil disables the guard
    # @return [void]
    # @raise [DescriptorError] on any structural rule violation
    def initialize(name:, kind:, descriptor:, source: nil, **rest)
      source = name if source.nil?
      if_callable = rest[:if]
      StructuralValidation.validate_symbol!("Association#name", name)
      StructuralValidation.validate_kind!("Association#kind", kind)
      StructuralValidation.validate_descriptor!("Association#descriptor", descriptor)
      StructuralValidation.validate_symbol!("Association#source", source)
      StructuralValidation.validate_callable!("Association#if", if_callable) unless if_callable.nil?
      super(name: name, kind: kind, descriptor: descriptor, source: source, if: if_callable)
    end
  end

  # Allowed values for +Association#kind+. Anything outside this set raises
  # +DescriptorError+ at +.new+.
  Association::KINDS = %i[has_one has_many].freeze

  # The input to Compile — an immutable, normalized description of one
  # serializer (per +docs/descriptor.md § Descriptor+). Carries the
  # human-readable identifier, the optional Models hint that unlocks
  # compile-time specialization, and the three Field-kind arrays
  # (+attributes+, +method_attributes+, +associations+). Frozen on
  # construction; structural validation runs once at +.new+ and raises
  # +DescriptorError+ on shape violations. Children are validated at their
  # own +.new+ — Descriptor only enforces array-element type, not the inner
  # Field shape.
  Descriptor = Data.define(:name, :models, :attributes, :method_attributes, :associations) do
    # Validates +name+ is a non-empty String, +models+ is +nil+ or an
    # +Array<Class>+, and the three Field-kind arrays contain only their
    # corresponding +Data+ types.
    #
    # @param name [String] human-readable identifier; non-empty
    # @param models [Array<Class>, nil] Record class hint; +nil+ uses the
    #   generic path
    # @param attributes [Array<Attribute>] direct-read Fields
    # @param method_attributes [Array<MethodAttribute>] Callable-driven Fields
    # @param associations [Array<Association>] nested-Descriptor Fields
    # @return [void]
    # @raise [DescriptorError] on any structural rule violation
    def initialize(name:, models:, attributes:, method_attributes:, associations:)
      StructuralValidation.validate_non_empty_string!("Descriptor#name", name)
      StructuralValidation.validate_models!("Descriptor#models", models)
      StructuralValidation.validate_array_of!("Descriptor#attributes", attributes, Attribute, "Attribute")
      StructuralValidation.validate_array_of!("Descriptor#method_attributes", method_attributes, MethodAttribute, "MethodAttribute")
      StructuralValidation.validate_array_of!("Descriptor#associations", associations, Association, "Association")
      super
    end
  end
end
