# frozen_string_literal: true

module Panko::CodeGen
  module Validators
    # Raises UnknownSourceError when an Attribute source on an Active Record +model:+
    # is neither a column nor an instance method. Other models are not checked.
    module SourceResolution
      def self.validate(descriptor, output:, config:)
        walk(descriptor, {})
        nil
      end

      class << self
        private

        def walk(descriptor, seen)
          return if seen[descriptor.__id__]
          seen[descriptor.__id__] = true
          classify_attributes!(descriptor) if descriptor.model
          descriptor.associations.each { |assoc| assoc.descriptors.each { |child| walk(child, seen) } }
        end

        def classify_attributes!(descriptor)
          model = descriptor.model
          return unless ar_class?(model)
          ActiveRecord::DefineAttributeMethods.ensure!(model)
          descriptor.attributes.each do |attribute|
            classify_or_raise!(model, attribute, descriptor.name)
          end
        end

        # The classifier knows only the class and the source; add the Descriptor and Field names.
        def classify_or_raise!(model, attribute, descriptor_name)
          ActiveRecord::AccessClassifier.classify(model, attribute.source)
          nil
        rescue UnknownSourceError
          raise UnknownSourceError,
            "#{descriptor_name}##{attribute.name}: Attribute#source :#{attribute.source} " \
            "is not a column or instance method on #{model.name}."
        end

        def ar_class?(klass)
          klass.respond_to?(:columns_hash) && klass.respond_to?(:attribute_methods_generated?)
        end
      end
    end
  end
end
