# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # Reads the bytecode of a serializer's methods for the instance variables they
    # set, so +_release+ clears exactly those and a serializer that sets none pays nothing.
    module WrittenIvars
      # Calls through which a method can set an instance variable, or check that one is set,
      # without naming it in the bytecode.
      REFLECTIVE_CALLS = %i[
        instance_variable_set instance_variable_defined? instance_variables
        instance_eval instance_exec eval binding
      ].freeze

      module_function

      # Each written name maps to whether a method checks it with +defined?+, or nil when
      # a method can set or check one the scan cannot name. Names are sorted: method table order
      # varies between runs, and the generated code must not.
      # +initialize+ is skipped: a Generated Class defines its own, so the serializer's never runs on it.
      def of(klass)
        return nil unless defined?(RubyVM::InstructionSequence)
        written = {}
        checked = {}
        klass.ancestors.each do |mod|
          break if mod.equal?(Object)
          (mod.instance_methods(false) + mod.private_instance_methods(false)).each do |name|
            next if name == :initialize
            return nil unless collect(mod.instance_method(name), written, checked)
          end
        end
        written.keys.sort.to_h { |name| [name, checked.key?(name)] }
      end

      # False when the method can set an instance variable without naming it.
      def collect(method, written, checked)
        iseq = RubyVM::InstructionSequence.of(method)
        return collect_native(method, written) if iseq.nil?
        walk(iseq, written, checked)
      end

      # +attr_writer+ and +attr_reader+ have no bytecode but a source location; a C method has neither.
      def collect_native(method, written)
        return false if method.source_location.nil?
        written[:"@#{method.name.to_s.chomp("=")}"] = true if method.name.end_with?("=")
        true
      end

      # Reads only the instruction list: the rest of +to_a+ holds locals and literals, which are data.
      # Every call instruction carries its call data, with the method name, as the first operand.
      def walk(iseq, written, checked)
        iseq.to_a.last.each do |instruction|
          next unless instruction.is_a?(Array)
          operand = instruction[1]
          case instruction[0]
          when :setinstancevariable then written[operand] = true
          when :definedivar then checked[operand] = true
          else
            return false if operand.is_a?(Hash) && REFLECTIVE_CALLS.include?(operand[:mid])
          end
        end
        iseq.to_enum(:each_child).all? { |child| walk(child, written, checked) }
      end
    end
  end
end
