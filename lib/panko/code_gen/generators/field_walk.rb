# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # Both Record-access strategies and both output modes share this walk,
    # so field order and filter indexes cannot differ between them.
    module FieldWalk
      module_function

      # +attribute_emit+ lets the Specialized strategy pick each Attribute's
      # read from the Model's column metadata instead of one +read_expr+ for all.
      def emit_fields(descriptor, config, field_index, builder, sink, read_expr:, attribute_emit: nil)
        sink.open_record(builder)
        descriptor.attributes.each do |attribute|
          index = field_index.fetch(GeneratedNames.filter_key(attribute))
          if attribute_emit
            attribute_emit.call(attribute, index)
          else
            sink.attribute(attribute, read_expr.call(attribute.source), config, index, builder)
          end
        end
        descriptor.associations.each do |association|
          sink.association(
            association, read_expr.call(association.source), config,
            field_index.fetch(GeneratedNames.filter_key(association)), builder
          )
        end
        descriptor.method_attributes.each do |method_attribute|
          sink.method_attribute(
            method_attribute, config,
            field_index.fetch(GeneratedNames.filter_key(method_attribute)), builder
          )
        end
        sink.close_record(builder)
      end
    end
  end
end
