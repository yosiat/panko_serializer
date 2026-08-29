# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # The one canonical field walk: record frame + Attributes →
    # Associations → Method Attributes in declared order, every Field
    # fetched from +field_index+ by +GeneratedNames.filter_key+. Both
    # Record-access strategies and both Output Mode adapters share this
    # walk, so field ordering, the filter-index parity, and the record
    # frame can't diverge between paths — the class of bug where the
    # Specialized walk cast leaf values differently from the Generic one.
    module FieldWalk
      module_function

      # Emits one record body through +sink+. The record-read expression
      # comes from +read_expr+; the Specialized strategy overrides the
      # per-Attribute emit via +attribute_emit+ (its reads are chosen by
      # column classification, not by one uniform expression).
      #
      # @param descriptor [Panko::CodeGen::Descriptor]
      # @param config [Panko::CodeGen::Config]
      # @param field_index [Hash{Symbol => Integer}]
      # @param builder [Panko::CodeGen::CodeBuilder]
      # @param sink [Panko::CodeGen::Generators::Sink]
      # @param read_expr [Proc] Source name → record-read Ruby source
      # @param attribute_emit [Proc, nil] (attribute, index) → void;
      #   defaults to the sink's plain attribute emit
      # @return [void]
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
