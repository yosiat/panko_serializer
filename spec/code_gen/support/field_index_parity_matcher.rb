# frozen_string_literal: true

require "rspec/expectations"

module Panko::CodeGen
  module Spec
    # Pins the +Field-index parity+ contract from
    # +docs/filters.md § Threading through Composition+: every
    # +unless filters.drops?(N) ... end+ wrapper emitted by the
    # +FieldEmitters::*+ helpers must carry the same integer that the
    # enclosing class's +FIELD_INDEX = {...}.freeze+ literal binds for
    # that wrapper's Field. The two are produced from one source —
    # +Generators::FieldIndex.build+'s filter-key map (+name+ for value
    # Fields, +source+ for Associations) — and consumers in the
    # per-emitter helpers fetch by that same key rather than by
    # iteration position. This matcher proves the discipline holds: if a
    # future emitter ever drifts to positional indexing or
    # {FieldIndex.build}'s declared order changes without a name-keyed
    # fetch, one of the per-class assertions fails.
    #
    # The matcher takes the full source string emitted by
    # {Panko::CodeGen::Generator#emit} (one or more top-level
    # +class <Name>_<Suffix>+ blocks) and walks every class block
    # independently. For each block it parses +FIELD_INDEX+ from the
    # literal, scans every +unless filters.drops?(N)+ wrapper, derives
    # the wrapper's Field name by locating a unique +FIELD_INDEX+ key
    # token in the wrapper body, and asserts +N == FIELD_INDEX[name]+.
    module FieldIndexParity
      # Top-level +class <Name>_<Suffix>+ block — the +<Name>_<Suffix>+
      # capture pairs the +FIELD_INDEX+ literal with the wrappers that
      # live inside it. Matches the emit shape from
      # +Generators::JsonMode#emit+ / +Generators::HashMode#emit+: every
      # Generated Class is a top-level class declaration with an
      # un-indented +end+ closing the block.
      CLASS_BLOCK_RE = /^class (\w+_(?:JSON|Hash))$\n(.*?)\n^end$/m

      # +FIELD_INDEX = {name: 0, name2: 1, ...}.freeze+ — the canonical
      # literal emitted by +Generators::FieldIndex.to_hash_literal+. The
      # body capture groups every +symbol: integer+ pair so the matcher
      # can re-hydrate a +Hash{Symbol => Integer}+ without an +eval+.
      FIELD_INDEX_RE = /^\s*FIELD_INDEX = \{([^}]*)\}\.freeze$/

      # Single +name: integer+ pair inside the +FIELD_INDEX+ literal.
      # Names use Ruby's identifier-symbol shorthand and integers are
      # base-10, so the pair regex is the simplest form.
      PAIR_RE = /(\w+):\s*(\d+)/

      # +unless filters.drops?(N)+ wrapper. The leading-whitespace
      # capture group anchors the closing +end+ at the same column,
      # avoiding overshoot into nested +if/unless...end+ blocks (the
      # +Association+ +if:+ guard, the +has_one+ +nil+ branch, etc.).
      DROPS_RE = /^([ \t]+)unless filters\.drops\?\((\d+)\)$\n(.*?)\n\1end$/m

      module_function

      # Walks +source+'s class blocks and returns the list of parity
      # failures (empty when parity holds). Each failure describes one
      # wrapper whose baked integer disagreed with its Field's
      # +FIELD_INDEX+ entry, or one wrapper whose body contained no /
      # multiple Field-name tokens.
      #
      # @param source [String] the Generator-emitted Ruby source for a
      #   whole Descriptor tree
      # @return [Array<String>] human-readable per-wrapper failure
      #   messages; empty when parity holds
      def failures(source)
        out = []
        source.scan(CLASS_BLOCK_RE).each do |class_name, body|
          field_index = parse_field_index(body)
          next if field_index.nil? || field_index.empty?
          out.concat(verify_class(class_name, body, field_index))
        end
        out
      end

      # Returns the +Symbol => Integer+ map parsed from the first
      # +FIELD_INDEX = {...}.freeze+ line in +body+, or +nil+ when none
      # is present (e.g. a class block emitted without a Filter map).
      #
      # @param body [String] the interior of one +class ... end+ block
      # @return [Hash{Symbol => Integer}, nil]
      def parse_field_index(body)
        match = body.match(FIELD_INDEX_RE)
        return nil unless match
        pairs = match[1].scan(PAIR_RE)
        pairs.each_with_object({}) { |(name, idx), h| h[name.to_sym] = idx.to_i }
      end

      # Returns the per-wrapper failure list for one class block. The
      # block's +FIELD_INDEX+ has already been parsed and is supplied in
      # +field_index+; +body+ is the raw +class ... end+ interior so
      # every +unless filters.drops?(N)+ wrapper at any nesting depth
      # is in scope.
      #
      # @param class_name [String] the +<Name>_<Suffix>+ identifier
      #   (used in failure messages)
      # @param body [String] the interior of one +class ... end+ block
      # @param field_index [Hash{Symbol => Integer}] parsed from the
      #   block's +FIELD_INDEX+ literal
      # @return [Array<String>] per-wrapper failure messages
      def verify_class(class_name, body, field_index)
        failures = []
        body.scan(DROPS_RE).each do |_indent, n_str, wrapper_body|
          n = n_str.to_i
          name = identify_field_name(wrapper_body, field_index.keys)
          if name.nil?
            failures << "#{class_name}: wrapper `unless filters.drops?(#{n})` " \
              "matches no unique FIELD_INDEX name in its body — cannot verify parity"
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

      # Returns the single +FIELD_INDEX+ name whose Field-emit token
      # appears in +wrapper_body+, or +nil+ when zero or multiple names
      # match.
      #
      # The token set covers every emit shape in
      # +Generators::FieldEmitters::{Attribute,MethodAttribute,Association}+
      # for the default (+:string+ output keys, no JSON-column wire
      # format) configurations exercised by the parity spec:
      #
      # - +"<name>"+ — quoted-string occurrences in
      #   +writer.push_value(_, "<name>")+ / +writer.push_key("<name>")+ /
      #   +writer.push_array("<name>")+ / +result["<name>"] = ...+.
      # - +@<name>_serializer+ — the per-Association nested ivar.
      # - +@cb_<name>.call+ — the per-MethodAttribute Callable ivar.
      # - +@cb_if_<name>.call+ — the per-Association +if:+ guard ivar.
      # - +filters.child(:<name>,+ — the per-Association child-filter
      #   call, keyed by +source+. The only token an *aliased*
      #   Association's wrapper carries for its FIELD_INDEX key (the
      #   other Association tokens use the output name).
      #
      # The wrapper body for any single Field always contains at least
      # one of these tokens, and (in the parity-spec's fixtures) only
      # one Field's tokens at a time, so a unique match identifies the
      # Field. Zero matches or multiple matches both yield +nil+ — the
      # caller reports a "cannot verify parity" failure rather than
      # silently passing.
      #
      # @param wrapper_body [String] interior of one
      #   +unless filters.drops?(N) ... end+ block
      # @param names [Array<Symbol>] the FIELD_INDEX keys for the
      #   enclosing class
      # @return [Symbol, nil]
      def identify_field_name(wrapper_body, names)
        matches = names.select do |name|
          wrapper_body.match?(name_pattern(name))
        end
        return nil if matches.size != 1
        matches.first
      end

      # Returns a regex matching any of the per-Field emit tokens for
      # +name+. See {.identify_field_name} for the token catalog.
      #
      # @param name [Symbol] Field name from +FIELD_INDEX+
      # @return [Regexp]
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
