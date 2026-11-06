# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    class ClassEmitter
      def initialize(sink)
        @sink = sink
      end

      def emit(descriptor, config)
        builder = CodeBuilder.new
        builder.line "# frozen_string_literal: true"
        builder.blank
        Banner.emit(builder, descriptor, output: @sink.output, config: config)
        cyclic_ids = CycleMembership.cyclic_descriptor_ids(descriptor)
        DescriptorWalk.in_emit_order(descriptor).each_with_index do |desc, i|
          builder.blank if i > 0
          emit_class(desc, config, builder, cyclic_ids)
        end
        builder.to_s + "\n"
      end

      # Public so {Generators::Fanout} can write one class per file.
      def emit_class(descriptor, config, builder, cyclic_ids)
        field_index = FieldIndex.build(descriptor)
        builder.line class_line(descriptor)
        builder.indent do
          builder.line "#{GeneratedNames.field_index_const} = #{FieldIndex.to_hash_literal(field_index)}.freeze"
          @sink.emit_class_constants(descriptor, config, builder)
          builder.blank
          emit_initialize(descriptor, builder, cyclic_ids)
          builder.blank
          @sink.emit_serialize_one(config, builder)
          builder.blank
          @sink.emit_serialize_many(config, builder)
          builder.blank
          Release.emit(descriptor, builder, cyclic_ids)
          builder.blank
          if descriptor.model.nil?
            RecordAccess::Generic.emit(descriptor, config, field_index, builder, @sink)
          else
            RecordAccess::Specialized.emit(descriptor, config, field_index, builder, @sink)
          end
          if config.supports_root_key
            builder.blank
            emit_validate_root_key(builder)
          end
        end
        builder.line "end"
      end

      private

      # An anonymous parent class has no name to write into the source, so
      # it is fetched from the +ANON_PARENTS+ constant instead.
      def class_line(descriptor)
        class_name = GeneratedNames.class_name(descriptor, @sink.suffix)
        if descriptor.parent_class.name
          "class #{class_name} < #{descriptor.parent_class.name}"
        else
          "class #{class_name} < ANON_PARENTS.fetch(#{descriptor.name.inspect})"
        end
      end

      # A Descriptor in a recursion cycle registers +self+ in +_construct_cache+
      # before building its children, so the cycle reuses this instance.
      def emit_initialize(descriptor, builder, cyclic_ids)
        cyclic_self = cyclic_ids[descriptor.__id__]
        signature = cyclic_self ? "def initialize(descriptor:, _construct_cache: {})" : "def initialize(descriptor:)"
        builder.line signature
        builder.indent do
          builder.line "_construct_cache[descriptor.__id__] = self" if cyclic_self
          descriptor.method_attributes.each_with_index do |method_attribute, index|
            next if method_attribute.body.is_a?(Symbol)
            ivar = GeneratedNames.callable_ivar(method_attribute)
            builder.line "#{ivar} = descriptor.method_attributes[#{index}].body"
          end
          descriptor.associations.each_with_index do |assoc, i|
            if assoc.if
              builder.line "#{GeneratedNames.if_guard_ivar(assoc)} = descriptor.associations[#{i}].if"
            end
            builder.line emit_serializer_assignment(descriptor, assoc, i, cyclic_ids)
            assoc.variants.each_with_index do |variant, v|
              builder.line "#{GeneratedNames.variant_serializer_ivar(assoc, v)} = " \
                "#{GeneratedNames.class_name(variant, @sink.suffix)}.new(descriptor: descriptor.associations[#{i}].variants[#{v}])"
            end
          end
        end
        builder.line "end"
      end

      # The cache is passed only when both ends are cyclic: a child outside
      # the cycle has a constructor without the +_construct_cache:+ kwarg.
      def emit_serializer_assignment(descriptor, assoc, i, cyclic_ids)
        ivar = GeneratedNames.serializer_ivar(assoc)
        if assoc.descriptor.equal?(descriptor)
          "#{ivar} = self"
        elsif cyclic_ids[descriptor.__id__] && cyclic_ids[assoc.descriptor.__id__]
          "#{ivar} = (_construct_cache[descriptor.associations[#{i}].descriptor.__id__] ||= " \
            "#{GeneratedNames.class_name(assoc.descriptor, @sink.suffix)}.new(descriptor: descriptor.associations[#{i}].descriptor, _construct_cache: _construct_cache))"
        else
          "#{ivar} = #{GeneratedNames.class_name(assoc.descriptor, @sink.suffix)}.new(descriptor: descriptor.associations[#{i}].descriptor)"
        end
      end

      def emit_validate_root_key(builder)
        builder.line "private def validate_root_key!(root_key)"
        builder.indent do
          builder.line "return if root_key.nil? || (root_key.is_a?(String) && !root_key.empty?)"
          builder.line %(raise ArgumentError, "root_key: must be a non-empty String, got \#{root_key.inspect}")
        end
        builder.line "end"
      end
    end
  end
end
