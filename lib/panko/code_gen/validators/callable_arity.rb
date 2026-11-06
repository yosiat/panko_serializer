# frozen_string_literal: true

module Panko::CodeGen
  module Validators
    # Raises ArityError when a MethodAttribute body or an Association +if:+
    # has an arity outside 0..3.
    module CallableArity
      # The generator's call shapes cover only 0..3; it treats any other arity as 3.
      ALLOWED_ARITIES = 0..3

      # Walks by object identity, so a shared or self-recursive Descriptor is checked once.
      def self.validate(descriptor, output:, config:)
        walk(descriptor, {})
        nil
      end

      class << self
        private

        # A Symbol body names a method and has no arity to check.
        def walk(descriptor, seen)
          return if seen[descriptor.__id__]
          seen[descriptor.__id__] = true
          descriptor.method_attributes.each do |ma|
            next if ma.body.is_a?(Symbol)
            check_arity!(descriptor.name, ma.name, "MethodAttribute#body", ma.body.arity)
          end
          descriptor.associations.each do |assoc|
            check_arity!(descriptor.name, assoc.name, "Association#if", assoc.if.arity) if assoc.if
            assoc.descriptors.each { |child| walk(child, seen) }
          end
        end

        def check_arity!(descriptor_name, field_name, callable_label, arity)
          return if ALLOWED_ARITIES.include?(arity)
          raise ArityError,
            "#{descriptor_name}##{field_name}: #{callable_label} has arity #{arity}; must be 0, 1, 2, or 3."
        end
      end
    end
  end
end
