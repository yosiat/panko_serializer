# frozen_string_literal: true

require "rspec/expectations"

module Panko::CodeGen
  module Spec
    # Checks that every +unless filters.drops?(N)+ wrapper in emitted source carries
    # the integer its class's +FIELD_INDEX+ binds for that wrapper's Field.
    module FieldIndexParity
      CLASS_BLOCK_RE = /^class (\w+_(?:JSON|Hash))$\n(.*?)\n^end$/m

      FIELD_INDEX_RE = /^\s*FIELD_INDEX = \{([^}]*)\}\.freeze$/

      PAIR_RE = /(\w+):\s*(\d+)/

      # The closing +end+ must sit at the wrapper's own column, so the match does not
      # stop at the +end+ of a nested +if+/+unless+ inside the wrapper.
      DROPS_RE = /^([ \t]+)unless filters\.drops\?\((\d+)\)$\n(.*?)\n\1end$/m

      module_function

      def failures(source)
        out = []
        source.scan(CLASS_BLOCK_RE).each do |class_name, body|
          field_index = parse_field_index(body)
          next if field_index.nil? || field_index.empty?
          out.concat(verify_class(class_name, body, field_index))
        end
        out
      end

      def parse_field_index(body)
        match = body.match(FIELD_INDEX_RE)
        return nil unless match
        pairs = match[1].scan(PAIR_RE)
        pairs.each_with_object({}) { |(name, idx), h| h[name.to_sym] = idx.to_i }
      end

      def verify_class(class_name, body, field_index)
        failures = []
        body.scan(DROPS_RE).each do |_indent, n_str, wrapper_body|
          n = n_str.to_i
          name = identify_field_name(wrapper_body, field_index.keys)
          if name.nil?
            failures << "#{class_name}: wrapper `unless filters.drops?(#{n})` " \
              "matches no unique FIELD_INDEX name in its body - cannot verify parity"
            next
          end
          expected = field_index[name]
          if expected != n
            failures << "#{class_name}: wrapper `unless filters.drops?(#{n})` " \
              "emits Field :#{name}, but FIELD_INDEX[:#{name}] = #{expected}"
          end
        end
        failures
      end

      # Returns +nil+ when zero or several names match, so the caller reports a failure
      # instead of passing.
      def identify_field_name(wrapper_body, names)
        matches = names.select do |name|
          wrapper_body.match?(name_pattern(name))
        end
        return nil if matches.size != 1
        matches.first
      end

      def name_pattern(name)
        escaped = Regexp.escape(name.to_s)
        /
          "#{escaped}"                    # quoted output key
          | @#{escaped}_serializer\b      # association ivar
          | @cb_#{escaped}\.call          # method-attribute callable
          | @cb_if_#{escaped}\.call       # association if: guard
          | filters\.child\(:#{escaped},  # association child filter (source-keyed)
        /x
      end
    end
  end
end

RSpec::Matchers.define :have_field_index_parity do
  match do |source|
    @failures = Panko::CodeGen::Spec::FieldIndexParity.failures(source)
    @failures.empty?
  end

  failure_message do |_source|
    "Field-index parity violations:\n  - #{@failures.join("\n  - ")}"
  end
end
