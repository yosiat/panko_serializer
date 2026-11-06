# frozen_string_literal: true

module Panko::CodeGen
  module Validators
    # Raises NameCollisionError when two Fields at the same level share a name:
    # each Field writes its output under its name. The same name at different levels is fine.
    module NameUniqueness
      def self.validate(descriptor, output:, config:)
        walk(descriptor, {})
        nil
      end

      class << self
        private

        def walk(descriptor, seen_descriptors)
          return if seen_descriptors[descriptor.__id__]
          seen_descriptors[descriptor.__id__] = true
          check_level!(descriptor)
          descriptor.associations.each { |assoc| assoc.descriptors.each { |child| walk(child, seen_descriptors) } }
        end

        def check_level!(descriptor)
          seen_names = {}
          fields_with_kinds(descriptor).each do |field, kind|
            previous_kind = seen_names[field.name]
            if previous_kind
              raise NameCollisionError,
                "#{descriptor.name}##{field.name}: #{previous_kind} and #{kind} share name; " \
                "every Field at the same level must have a unique name."
            end
            seen_names[field.name] = kind
          end
        end

        def fields_with_kinds(descriptor)
          descriptor.attributes.map { |a| [a, "Attribute"] } +
            descriptor.method_attributes.map { |m| [m, "MethodAttribute"] } +
            descriptor.associations.map { |a| [a, "Association"] }
        end
      end
    end
  end
end
