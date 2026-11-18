# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # Reads the bytecode of a serializer's methods for the instance variables they
    # set, so +_release+ clears exactly those and a serializer that sets none pays nothing.
    module WrittenIvars
      # Calls through which a method can set an instance variable the bytecode does not name.
      REFLECTIVE_CALLS = %i[instance_variable_set instance_eval instance_exec eval binding].freeze

      module_function

      # The names, or nil when a method can set one the scan cannot name.
      # +initialize+ is skipped: a Generated Class defines its own, so the serializer's never runs on it.
      def of(klass)
        return nil unless defined?(RubyVM::InstructionSequence)
        names = {}
        klass.ancestors.each do |mod|
          break if mod.equal?(Object)
          (mod.instance_methods(false) + mod.private_instance_methods(false)).each do |name|
            next if name == :initialize
            return nil unless collect(mod.instance_method(name), names)
          end
        end
        names.keys
      end

      # False when the method can set an instance variable without naming it.
      def collect(method, names)
        iseq = RubyVM::InstructionSequence.of(method)
        return collect_native(method, names) if iseq.nil?
        walk(iseq, names)
      end

      # +attr_writer+ and +attr_reader+ have no bytecode but a source location; a C method has neither.
      def collect_native(method, names)
        return false if method.source_location.nil?
        names[:"@#{method.name.to_s.chomp("=")}"] = true if method.name.end_with?("=")
        true
      end

      # Reads only the instruction list: the rest of +to_a+ holds locals and literals, which are data.
      # Every call instruction carries its call data, with the method name, as the first operand.
      def walk(iseq, names)
        iseq.to_a.last.each do |instruction|
          next unless instruction.is_a?(Array)
          operand = instruction[1]
          if instruction[0] == :setinstancevariable
            names[operand] = true
          elsif operand.is_a?(Hash) && REFLECTIVE_CALLS.include?(operand[:mid])
            return false
          end
        end
        iseq.to_enum(:each_child).all? { |child| walk(child, names) }
      end
    end
  end
end
