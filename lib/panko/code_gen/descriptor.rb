# frozen_string_literal: true

module Panko::CodeGen
  # Returned by a Method Attribute body to omit its Field. Compared by
  # identity, so no caller value can be mistaken for it.
  SKIP = Object.new.freeze

  # Each Descriptor-family +Data+ type validates its own fields at +.new+,
  # so +Descriptor+ checks only the type of each array element, not its fields.
  module StructuralValidation
    module_function

    def validate_symbol!(field, value)
      return if value.is_a?(Symbol)
      raise DescriptorError, "#{field}: must be a Symbol; got #{value.inspect}:#{value.class}"
    end

    def validate_callable!(field, value)
      return if value.is_a?(Symbol)
      if value.is_a?(UnboundMethod)
        raise DescriptorError, "#{field}: must be a bound Callable, not an UnboundMethod; got #{value.inspect}:#{value.class}"
      end
      return if value.respond_to?(:call)
      raise DescriptorError, "#{field}: must respond to #call; got #{value.inspect}:#{value.class}"
    end

    def validate_optional_class!(field, value)
      return if value.nil?
      return if value.is_a?(Class)
      raise DescriptorError, "#{field}: must be a Class or nil; got #{value.inspect}:#{value.class}"
    end

    def validate_class!(field, value)
      return if value.is_a?(Class)
      raise DescriptorError, "#{field}: must be a Class; got #{value.inspect}:#{value.class}"
    end

    def validate_non_empty_string!(field, value)
      return if value.is_a?(String) && !value.empty?
      raise DescriptorError, "#{field}: must be a non-empty String; got #{value.inspect}:#{value.class}"
    end

    # +kind_label+ is passed apart from +element_class+ so the namespace
    # does not show in the error message.
    def validate_array_of!(field, value, element_class, kind_label)
      unless value.is_a?(Array)
        raise DescriptorError, "#{field}: must be an Array of #{kind_label}; got #{value.inspect}:#{value.class}"
      end
      value.each do |el|
        next if el.is_a?(element_class)
        raise DescriptorError, "#{field}: must contain only #{kind_label} elements; got #{el.inspect}:#{el.class}"
      end
    end

    def validate_descriptor!(field, value)
      return if value.is_a?(Descriptor)
      raise DescriptorError, "#{field}: must be a Descriptor; got #{value.inspect}:#{value.class}"
    end

    def validate_kind!(field, value)
      return if Association::KINDS.include?(value)
      raise DescriptorError, "#{field}: must be :has_one or :has_many; got #{value.inspect}:#{value.class}"
    end
  end

  # A Field read from the Record's +source+ (defaults to +name+).
  Attribute = Data.define(:name, :source) do
    def initialize(name:, source: name)
      StructuralValidation.validate_symbol!("Attribute#name", name)
      StructuralValidation.validate_symbol!("Attribute#source", source)
      super
    end
  end

  # +body+ is a Callable (passed record, context, scope up to its arity) or a Symbol
  # naming a +parent_class+ method; returning +SKIP+ omits the Field.
  MethodAttribute = Data.define(:name, :body) do
    def initialize(name:, body:)
      StructuralValidation.validate_symbol!("MethodAttribute#name", name)
      StructuralValidation.validate_callable!("MethodAttribute#body", body)
      super
    end
  end

  # +descriptor+ may be the parent itself for self-recursive shapes.
  Association = Data.define(:name, :kind, :descriptor, :source, :if, :variants) do
    # +variants+ serve a source returning several record classes: a record uses the
    # variant whose +model+ is its exact class, else +descriptor+.
    def initialize(name:, kind:, descriptor:, source: nil, if: nil, variants: [])
      # +if+ is a keyword, so its value cannot be read as a local by name.
      if_callable = binding.local_variable_get(:if)
      source = name if source.nil?
      StructuralValidation.validate_symbol!("Association#name", name)
      StructuralValidation.validate_kind!("Association#kind", kind)
      StructuralValidation.validate_descriptor!("Association#descriptor", descriptor)
      StructuralValidation.validate_symbol!("Association#source", source)
      # +if+ must be a Callable: a Symbol passes this check but fails at compile
      # (Symbol has no +arity+).
      StructuralValidation.validate_callable!("Association#if", if_callable) unless if_callable.nil?
      StructuralValidation.validate_array_of!("Association#variants", variants, Descriptor, "Descriptor")
      validate_variants!(variants)
      super(name: name, kind: kind, descriptor: descriptor, source: source, if: if_callable, variants: variants.frozen? ? variants : variants.dup.freeze)
    end

    def descriptors
      variants.empty? ? [descriptor] : [descriptor, *variants]
    end

    private

    def validate_variants!(variants)
      models = variants.map(&:model)
      if models.any? { |model| model.nil? || model.name.nil? }
        raise DescriptorError, "Association#variants: every variant needs a named model; got #{models.inspect}"
      end
      return if models.uniq.size == models.size
      raise DescriptorError, "Association#variants: models must be distinct; got #{models.inspect}"
    end
  end

  Association::KINDS = %i[has_one has_many].freeze

  # +model+ nil uses the generic path, a Class allows specialization; the Generated
  # Class subclasses +parent_class+.
  Descriptor = Data.define(:name, :model, :attributes, :method_attributes, :associations, :parent_class) do
    def initialize(name:, model:, attributes:, method_attributes:, associations:, parent_class:)
      StructuralValidation.validate_non_empty_string!("Descriptor#name", name)
      StructuralValidation.validate_optional_class!("Descriptor#model", model)
      StructuralValidation.validate_array_of!("Descriptor#attributes", attributes, Attribute, "Attribute")
      StructuralValidation.validate_array_of!("Descriptor#method_attributes", method_attributes, MethodAttribute, "MethodAttribute")
      StructuralValidation.validate_array_of!("Descriptor#associations", associations, Association, "Association")
      StructuralValidation.validate_class!("Descriptor#parent_class", parent_class)
      super
    end
  end
end
