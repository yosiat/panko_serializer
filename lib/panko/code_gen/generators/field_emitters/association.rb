# frozen_string_literal: true

module SerializersCodeGen
  module Generators
    module FieldEmitters
      # Emits the per-mode write for one +Association+ inside a
      # +_write_one_*+ / +_to_hash_*+ helper. Composition shape per
      # +docs/compilation.md § Composition of nested Associations+: the
      # parent's constructor has hoisted +@<name>_serializer+ pointing at
      # an instance of the nested Generated Class; the emit here calls
      # through that ivar.
      #
      # Per-Association precedence ladder per
      # +docs/filters.md § Filter before if:+ and
      # +docs/testing.md § association_if_spec.rb § Precedence ladder+:
      # Filter > +if:+ > Source. The codegen mirrors the order — the
      # +unless filters.drops?(<index>)+ wrapper is the outermost guard,
      # the +if @cb_if_<name>.call(...)+ wrap (when present) lives inside
      # it, and only inside that wrap does the per-Kind body read the
      # Source. A filter-dropped Association never calls its +if:+
      # Callable and never loads its Source.
      #
      # Nested calls thread +filters.child(:<source>)+ rather than the
      # parent's +filters+ object verbatim — Filters do not inherit per
      # +docs/filters.md § Rules+ ("+:only+ at the parent level does not
      # propagate to child Associations. Children are governed by their
      # own sub-hash (or are unfiltered if none is supplied)."). The
      # +Source+ (not the +name+) is the lookup key per
      # +docs/filters.md § Public shape+. For +has_many+ the +#child+
      # lookup is hoisted to a +child_filter+ local above the iteration
      # so the Filter cell's child cache is consulted at most once per
      # +(Association, Record)+ pair rather than once per element.
      #
      # S5.1 shipped +has_one+; S5.2 adds +has_many+ (collection emit:
      # +writer.push_array+ + element iteration + +writer.pop+ in JSON;
      # +.map+ on the collection in Hash). S5.3 adds the +Association#if+
      # Callable wrap — when +association.if+ is non-+nil+ the entire
      # per-Kind emit is wrapped in
      # +if @cb_if_<name>.call(...) ... end+ with arity-specialized
      # invocation per +docs/descriptor.md § Callable arity+; when +nil+
      # no wrap is emitted (zero runtime cost — no branch, no Callable
      # dispatch, no +@cb_if_<name>+ ivar hoisted by the constructor).
      # The +if:+ wrap precedes the Source read so a falsy guard never
      # invokes the Source per +docs/testing.md § association_if_spec.rb
      # § Precedence ladder+ (item 2 wins over item 3; +if:+ falsy
      # short-circuits before either +null_for_missing_has_one+ branch
      # of +has_one+ or the +has_many+ collection iteration runs). Both
      # +null_for_missing_has_one+ branches (default-+true+ → emit
      # +null+/+nil+; +false+ → omit the key) are emitted as compile-time
      # source choices keyed off +Config#null_for_missing_has_one+ for
      # the +has_one+ Kind only; +has_many+ ignores the knob (an empty
      # collection always emits +[]+ — never +null+, never omitted) per
      # +docs/output-modes.md § Null Association handling+. The
      # +null_for_missing_has_one: false+ branch is exercised end-to-end
      # by S10's +config_null_for_has_one_off+ fixture; this slice only
      # pins the default-+true+ branch.
      module Association
        # Emits the JSON-mode write for one Association, dispatching on
        # +association.kind+ to the per-Kind helper.
        #
        # +has_one+ — default (+null_for_missing_has_one: true+) emits:
        #   value = <source_read_expr>
        #   if value.nil?
        #     writer.push_value(nil, "<name>")
        #   else
        #     writer.push_key("<name>")
        #     @<name>_serializer._write_one(value, writer, context, scope, filters.child(:<source>, <Child>_JSON::FIELD_INDEX))
        #   end
        #
        # +has_one+ — omit-when-nil (+null_for_missing_has_one: false+) emits:
        #   value = <source_read_expr>
        #   unless value.nil?
        #     writer.push_key("<name>")
        #     @<name>_serializer._write_one(value, writer, context, scope, filters.child(:<source>, <Child>_JSON::FIELD_INDEX))
        #   end
        #
        # +has_many+ emits (config-independent — empty collection → +[]+):
        #   child_filter = filters.child(:<source>, <Child>_JSON::FIELD_INDEX)
        #   writer.push_array("<name>")
        #   <source_read_expr>.each do |element|
        #     @<name>_serializer._write_one(element, writer, context, scope, child_filter)
        #   end
        #   writer.pop
        #
        # The 2-arg +push_value(nil, "<name>")+ form on the +has_one+ nil
        # arm and the 2-arg +push_array("<name>")+ on +has_many+ collapse
        # a +push_key+ + opener pair into a single C-extension dispatch
        # (byte-identical output, fewer dispatches). The non-nil
        # +has_one+ arms keep the +push_key("<name>")+ + +_write_one+
        # split: the inner +_write_one+ opens its own +push_object+ frame
        # per +docs/compilation.md § Composition of nested Associations+,
        # so collapsing across that boundary would require restructuring
        # the +_write_one+ contract (a keyed-+_write_one+ variant or an
        # +_emit_fields+ helper that doesn't open its own frame).
        #
        # @param association [SerializersCodeGen::Association] the Field node
        # @param source_read_expr [String] Ruby source for fetching the
        #   related Record(s) (e.g. +"record[\"author\"]"+ or
        #   +"record.comments"+)
        # @param config [SerializersCodeGen::Config] resolved settings;
        #   +null_for_missing_has_one+ selects the +has_one+ emit branch
        # @param index [Integer] codegen-time +FIELD_INDEX+ position used
        #   in the +unless filters.drops?(<index>)+ wrapper
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json(association, source_read_expr, config, index, builder)
          builder.line "unless filters.drops?(#{index})"
          builder.indent do
            with_if_guard(association, builder) do
              emit_json_body(association, source_read_expr, config, builder)
            end
          end
          builder.line "end"
        end

        # Returns the Ruby source for the +filters.child(:<source>, ...)+
        # call at one Association's nested call site. The second argument
        # is the nested Generated Class's +FIELD_INDEX+ constant — the
        # parent statically knows the child class name from
        # +association.descriptor.name+ + the per-mode +suffix+ ("JSON" or
        # "Hash") since it constructs the +@<name>_serializer+ ivar
        # against that same class. Pinned at one place so the JSON and
        # Hash emit paths can't drift on the qualified-constant shape.
        #
        # The child class's +FIELD_INDEX+ is referenced by its fully
        # qualified name (e.g. +AuthorSerializer_JSON::FIELD_INDEX+)
        # rather than via +@<name>_serializer.class::FIELD_INDEX+ — the
        # constant lookup is a single +get_const+ on a literal token
        # (YJIT-inlinable, no method dispatch), and self-recursive
        # Descriptors resolve the constant against the in-scope class
        # (+RecursiveSelfCommentSerializer_JSON::FIELD_INDEX+ from inside
        # +RecursiveSelfCommentSerializer_JSON+'s body works because
        # constant resolution happens at method-execution time, by which
        # point the class is fully defined).
        #
        # @param association [SerializersCodeGen::Association] the Field node
        # @param suffix [String] +"JSON"+ or +"Hash"+ — the per-mode
        #   Generated Class suffix for the nested class
        # @return [String] Ruby source like
        #   +'filters.child(:author, AuthorSerializer_JSON::FIELD_INDEX)'+
        def self.child_filter_expr(association, suffix)
          "filters.child(:#{association.source}, #{association.descriptor.name}_#{suffix}::FIELD_INDEX)"
        end

        # Emits the per-Kind JSON body for one Association — the un-wrapped
        # emit shape used inside the optional +if @cb_if_<name>.call(...)+
        # guard (or directly when no guard is configured).
        #
        # @param association [SerializersCodeGen::Association]
        # @param source_read_expr [String]
        # @param config [SerializersCodeGen::Config]
        # @param builder [SerializersCodeGen::CodeBuilder]
        # @return [void]
        def self.emit_json_body(association, source_read_expr, config, builder)
          case association.kind
          when :has_one
            builder.line "value = #{source_read_expr}"
            if config.null_for_missing_has_one
              emit_json_has_one_default(association, builder)
            else
              emit_json_has_one_omit(association, builder)
            end
          when :has_many
            emit_json_has_many(association, source_read_expr, builder)
          end
        end

        # Emits the Hash-mode write for one Association, dispatching on
        # +association.kind+ to the per-Kind helper. Output-key shape
        # comes from +output_key_type+ (the +Config#hash_output_key_type+
        # value); only +:string+ is exercised in this slice (S10 covers
        # +:symbol+).
        #
        # +has_one+ — default (+null_for_missing_has_one: true+) emits:
        #   value = <source_read_expr>
        #   result[<key>] = if value.nil?
        #     nil
        #   else
        #     @<name>_serializer._to_hash(value, context, scope, filters)
        #   end
        #
        # +has_one+ — omit-when-nil (+null_for_missing_has_one: false+) emits:
        #   value = <source_read_expr>
        #   unless value.nil?
        #     result[<key>] = @<name>_serializer._to_hash(value, context, scope, filters)
        #   end
        #
        # +has_many+ emits (config-independent — empty collection → +[]+):
        #   result[<key>] = <source_read_expr>.map { |element| @<name>_serializer._to_hash(element, context, scope, filters) }
        #
        # @param association [SerializersCodeGen::Association] the Field node
        # @param source_read_expr [String] Ruby source for fetching the
        #   related Record(s)
        # @param output_key_type [Symbol] +:string+ or +:symbol+ — the
        #   pre-validated value of +Config#hash_output_key_type+
        # @param config [SerializersCodeGen::Config] resolved settings;
        #   +null_for_missing_has_one+ selects the +has_one+ emit branch
        # @param index [Integer] codegen-time +FIELD_INDEX+ position used
        #   in the +unless filters.drops?(<index>)+ wrapper
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_hash(association, source_read_expr, output_key_type, config, index, builder)
          key_lit = case output_key_type
          when :symbol then ":#{association.name}"
          else %("#{association.name}")
          end
          builder.line "unless filters.drops?(#{index})"
          builder.indent do
            with_if_guard(association, builder) do
              emit_hash_body(association, source_read_expr, key_lit, config, builder)
            end
          end
          builder.line "end"
        end

        # Emits the per-Kind Hash body for one Association — the un-wrapped
        # emit shape used inside the optional +if @cb_if_<name>.call(...)+
        # guard (or directly when no guard is configured).
        #
        # @param association [SerializersCodeGen::Association]
        # @param source_read_expr [String]
        # @param key_lit [String] pre-rendered Ruby literal for the output
        #   key
        # @param config [SerializersCodeGen::Config]
        # @param builder [SerializersCodeGen::CodeBuilder]
        # @return [void]
        def self.emit_hash_body(association, source_read_expr, key_lit, config, builder)
          case association.kind
          when :has_one
            builder.line "value = #{source_read_expr}"
            if config.null_for_missing_has_one
              emit_hash_has_one_default(association, key_lit, builder)
            else
              emit_hash_has_one_omit(association, key_lit, builder)
            end
          when :has_many
            emit_hash_has_many(association, source_read_expr, key_lit, builder)
          end
        end

        # Emits the JSON-mode default-true branch — branches first on
        # +value.nil?+: the nil arm collapses key+value into the 2-arg
        # +writer.push_value(nil, "<name>")+ form (one C-extension
        # dispatch); the non-nil arm pushes the key then dispatches to
        # the nested Generated Class's +_write_one+, which opens its own
        # +push_object+ frame internally per
        # +docs/compilation.md § Composition of nested Associations+. The
        # +push_key+ in the non-nil arm cannot be collapsed across that
        # frame boundary without restructuring +_write_one+'s contract.
        #
        # The non-nil arm threads +filters.child(:<source>)+ — the
        # +Source+ is the lookup key per
        # +docs/filters.md § Threading through Composition+ ("Filters do
        # not inherit"). Inlined at the call site for +has_one+ since
        # the call fires at most once per record (Filter cell caches
        # repeated +#child+ lookups but the inline form keeps the
        # snapshot diff minimal vs hoisting to a local).
        #
        # @param association [SerializersCodeGen::Association]
        # @param builder [SerializersCodeGen::CodeBuilder]
        # @return [void]
        def self.emit_json_has_one_default(association, builder)
          builder.line "if value.nil?"
          builder.indent { builder.line %(writer.push_value(nil, "#{association.name}")) }
          builder.line "else"
          builder.indent do
            builder.line %(writer.push_key("#{association.name}"))
            builder.line "@#{association.name}_serializer._write_one(value, writer, context, scope, #{child_filter_expr(association, "JSON")})"
          end
          builder.line "end"
        end

        # Emits the JSON-mode +null_for_missing_has_one: false+ branch
        # — omits the key entirely (no +push_key+, no +push_value+) when
        # the Source returns +nil+. When the Source is non-nil, pushes
        # the key then dispatches to the nested Generated Class's
        # +_write_one+, which opens its own +push_object+ frame
        # internally per
        # +docs/compilation.md § Composition of nested Associations+.
        # The +push_key+ here cannot be collapsed across that frame
        # boundary without restructuring +_write_one+'s contract.
        #
        # Threads +filters.child(:<source>)+ for the same reason as
        # {.emit_json_has_one_default}.
        #
        # @param association [SerializersCodeGen::Association]
        # @param builder [SerializersCodeGen::CodeBuilder]
        # @return [void]
        def self.emit_json_has_one_omit(association, builder)
          builder.line "unless value.nil?"
          builder.indent do
            builder.line %(writer.push_key("#{association.name}"))
            builder.line "@#{association.name}_serializer._write_one(value, writer, context, scope, #{child_filter_expr(association, "JSON")})"
          end
          builder.line "end"
        end

        # Emits the Hash-mode default-true branch — assigns the key with
        # +nil+ or the nested call via the +result[k] = if/else/end+
        # idiom. Threads +filters.child(:<source>)+ on the non-nil arm
        # per +docs/filters.md § Threading through Composition+.
        #
        # @param association [SerializersCodeGen::Association]
        # @param key_lit [String] pre-rendered Ruby literal for the
        #   output key (e.g. +'"author"'+ or +':author'+)
        # @param builder [SerializersCodeGen::CodeBuilder]
        # @return [void]
        def self.emit_hash_has_one_default(association, key_lit, builder)
          builder.line "result[#{key_lit}] = if value.nil?"
          builder.indent { builder.line "nil" }
          builder.line "else"
          builder.indent do
            builder.line "@#{association.name}_serializer._to_hash(value, context, scope, #{child_filter_expr(association, "Hash")})"
          end
          builder.line "end"
        end

        # Emits the Hash-mode +null_for_missing_has_one: false+ branch
        # — omits the key entirely (no assignment to +result+) when the
        # Source returns +nil+. Threads +filters.child(:<source>)+ on
        # the non-nil arm.
        #
        # @param association [SerializersCodeGen::Association]
        # @param key_lit [String] pre-rendered Ruby literal for the
        #   output key
        # @param builder [SerializersCodeGen::CodeBuilder]
        # @return [void]
        def self.emit_hash_has_one_omit(association, key_lit, builder)
          builder.line "unless value.nil?"
          builder.indent do
            builder.line "result[#{key_lit}] = @#{association.name}_serializer._to_hash(value, context, scope, #{child_filter_expr(association, "Hash")})"
          end
          builder.line "end"
        end

        # Emits the JSON-mode +has_many+ shape — opens a keyed array on
        # the Writer via the 2-arg +push_array("<name>")+ form (one
        # C-extension dispatch in place of +push_key+ + +push_array+),
        # iterates the Source collection element-by-element through the
        # nested Generated Class's +_write_one+, then closes the array.
        # An empty collection naturally emits +[]+ (no key omission, no
        # +null+ — empty array is its own state) per
        # +docs/output-modes.md § Null Association handling+.
        #
        # Hoists +child_filter = filters.child(:<source>)+ above the
        # iteration loop — one +#child+ call per Association per Record
        # rather than one per element. Matches the +indexed x
        # single_path+ winning cell from
        # +docs/research/filter_experiments_bench.rb+ (lines 586–595).
        #
        # @param association [SerializersCodeGen::Association]
        # @param source_read_expr [String] Ruby source for the parent
        #   Record's collection-returning Source (inlined into the
        #   +.each+ — no per-element local needed)
        # @param builder [SerializersCodeGen::CodeBuilder]
        # @return [void]
        def self.emit_json_has_many(association, source_read_expr, builder)
          builder.line "child_filter = #{child_filter_expr(association, "JSON")}"
          builder.line %(writer.push_array("#{association.name}"))
          builder.line "#{source_read_expr}.each do |element|"
          builder.indent do
            builder.line "@#{association.name}_serializer._write_one(element, writer, context, scope, child_filter)"
          end
          builder.line "end"
          builder.line "writer.pop"
        end

        # Emits the Hash-mode +has_many+ shape — assigns a fresh
        # +Array<Hash>+ via +.map+ over the Source collection, each
        # element passed through the nested Generated Class's
        # +_to_hash+. An empty collection emits an empty Array (the
        # +Array#map+ on +[]+ returns +[]+) per
        # +docs/output-modes.md § Null Association handling+.
        #
        # Hoists +child_filter = filters.child(:<source>)+ above the
        # +.map+ — same rationale as {.emit_json_has_many}.
        #
        # @param association [SerializersCodeGen::Association]
        # @param source_read_expr [String] Ruby source for the parent
        #   Record's collection-returning Source
        # @param key_lit [String] pre-rendered Ruby literal for the
        #   output key
        # @param builder [SerializersCodeGen::CodeBuilder]
        # @return [void]
        def self.emit_hash_has_many(association, source_read_expr, key_lit, builder)
          builder.line "child_filter = #{child_filter_expr(association, "Hash")}"
          builder.line(
            "result[#{key_lit}] = #{source_read_expr}.map { |element| " \
              "@#{association.name}_serializer._to_hash(element, context, scope, child_filter) }"
          )
        end

        # Wraps +block+ in +if @cb_if_<name>.call(...) ... end+ when
        # +association.if+ is non-+nil+, or yields the block directly
        # when no guard is configured. The wrap pre-empts the per-Kind
        # body — Source read, key push, nested call — so a falsy guard
        # short-circuits before any of them run, per
        # +docs/testing.md § association_if_spec.rb § Precedence ladder+.
        # Call expression is arity-specialized per
        # +docs/descriptor.md § Callable arity+ via
        # {.call_expression}.
        #
        # @param association [SerializersCodeGen::Association]
        # @param builder [SerializersCodeGen::CodeBuilder]
        # @yield emits the per-Kind body inside the guard
        # @return [void]
        def self.with_if_guard(association, builder)
          if association.if
            builder.line "if #{call_expression(ivar_name(association), association.if.arity)}"
            builder.indent { yield }
            builder.line "end"
          else
            yield
          end
        end

        # Returns the per-Association +if:+ ivar name used for both
        # constructor hoisting and the guard call site. Pinned at one
        # place so the constructor and the field emitter can't drift.
        #
        # @param association [SerializersCodeGen::Association] the Field node
        # @return [String] the ivar token, e.g. +"@cb_if_author"+
        def self.ivar_name(association)
          "@cb_if_#{association.name}"
        end

        # Returns the arity-specialized call expression for one ivar.
        # Pre-validated by the +callable_arity+ rule (S4.1, widened to
        # +0..3+ in S17.1) — only +0+, +1+, +2+, +3+ ever reach this
        # method. Mirrors the same arity-axis rule applied to
        # +MethodAttribute#body+ via
        # +FieldEmitters::MethodAttribute.call_expression+ — both Callable
        # surfaces share the per-arity emit shape per
        # +docs/descriptor.md § Callable arity+. Arity 3 threads +scope+
        # positionally as the third argument; arity 2 keeps its
        # +(record, context)+ meaning (no +scope+ leak).
        #
        # @param ivar_name [String] the +@cb_if_<name>+ ivar to invoke
        # @param arity [Integer] +0+, +1+, +2+, or +3+
        # @return [String] Ruby source like +"@cb_if_author.call(record, context)"+
        def self.call_expression(ivar_name, arity)
          case arity
          when 0 then "#{ivar_name}.call"
          when 1 then "#{ivar_name}.call(record)"
          when 2 then "#{ivar_name}.call(record, context)"
          else "#{ivar_name}.call(record, context, scope)"
          end
        end
      end
    end
  end
end
