# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # Mutual-recursion peers +require_relative+ each other. Ruby allows this because
    # a peer's constant is read only when a method runs, after both files have loaded.
    module Fanout
      module_function

      def emit_files(descriptor, output:, config:)
        cyclic_ids = CycleMembership.cyclic_descriptor_ids(descriptor)
        DescriptorWalk.in_emit_order(descriptor).map do |desc|
          {
            descriptor: desc,
            basename: basename_for(desc, output),
            source: build_file(desc, output, config, cyclic_ids)
          }
        end
      end

      def basename_for(descriptor, output)
        "#{snake_case(descriptor.name)}_#{output}.rb"
      end

      def snake_case(camel)
        camel.gsub(/(?<=.)([A-Z])/, '_\1').downcase
      end
      private_class_method :snake_case

      def build_file(descriptor, output, config, cyclic_ids)
        builder = CodeBuilder.new
        builder.line "# frozen_string_literal: true"
        builder.blank
        Banner.emit(builder, descriptor, output: output, config: config)
        deps = ordered_dependencies(descriptor)
        deps.each do |dep|
          builder.line %(require_relative "#{snake_case(dep.name)}_#{output}")
        end
        builder.blank if deps.any?
        emitter = ClassEmitter.new(Panko::CodeGen::Generator.sink_for(output))
        emitter.emit_class(descriptor, config, builder, cyclic_ids)
        builder.to_s + "\n"
      end
      private_class_method :build_file

      # Seeded with +descriptor+ itself: a self-loop needs no +require_relative+.
      def ordered_dependencies(descriptor)
        seen = {descriptor.__id__ => true}
        deps = []
        descriptor.associations.flat_map(&:descriptors).each do |target|
          next if seen[target.__id__]
          seen[target.__id__] = true
          deps << target
        end
        deps
      end
      private_class_method :ordered_dependencies
    end
  end
end
