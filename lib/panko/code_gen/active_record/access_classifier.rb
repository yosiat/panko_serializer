# frozen_string_literal: true

module Panko::CodeGen
  module ActiveRecord
    # Source-classification rule for the Specialized path. Encodes the
    # 3-step rule
    # once (column with AR's own reader → +:column+; instance method →
    # +:method+; else raise) so the +Generator+ and the
    # +SourceResolution+ validator never duplicate it.
    #
    # Surface is one method (+.classify(klass, source)+); internals are
    # duck-typed against +klass.columns_hash+ + +klass.method_defined?+
    # so unit coverage runs against fake AR-like classes without booting
    # a real ActiveRecord stack.
    module AccessClassifier
      # Classifies +source+ against +klass+:
      #
      # 1. Column-backed (+source+ in +klass.columns_hash+) AND the
      #    reader is AR's own auto-generated one → +:column+. The fast
      #    path — +record._read_attribute("name")+ returns exactly what
      #    the generated reader would.
      # 2. Else, instance method (+klass.method_defined?+, including a
      #    user-overridden column reader) → +:method+. A user override
      #    is honored, never bypassed: the Model is a compiler hint the
      #    seam applies on the caller's behalf, so a specialized body
      #    must stay observably identical to the Generic path's
      #    +record.<source>+ dispatch.
      # 3. Else (neither a column nor an instance method by +source+'s
      #    name) → raise +UnknownSourceError+.
      #
      # Caller is responsible for ensuring AR's lazy attribute methods
      # have been generated (via +DefineAttributeMethods.ensure!+) on
      # +klass+ before classification; the +SourceResolution+ validator
      # does this. Without +define_attribute_methods+ called first,
      # +method_defined?+ returns +false+ for column-name methods and
      # override-detection cannot distinguish auto-generated readers
      # from user overrides.
      #
      # @param klass [Class] the +Model+ class to introspect; must
      #   respond to +#columns_hash+ (a Hash keyed by column-name
      #   String), +#method_defined?+, and +#instance_method+ (whose
      #   result's +#owner+ is the defining +Module+ or +Class+)
      # @param source [Symbol, String] the +Attribute#source+ to classify;
      #   accepts either type since +columns_hash+ keys are Strings while
      #   +method_defined?+ accepts both
      # @return [Symbol] +:column+ when column-backed with AR's own
      #   reader; +:method+ when resolvable as an instance method
      #   (including user-overridden column readers)
      # @raise [Panko::CodeGen::UnknownSourceError] when +klass+ lacks
      #   both a column and an instance method by +source+'s name;
      #   message names the class and the +source+ but does not include
      #   +Descriptor+ / +Field+ context (the +SourceResolution+
      #   validator wraps the raise to satisfy the Message convention
      #   format)
      def self.classify(klass, source)
        if klass.columns_hash.key?(source.to_s)
          return user_override?(klass, source) ? :method : :column
        end
        return :method if klass.method_defined?(source)
        raise UnknownSourceError,
          "#{klass.name}: source :#{source} is not a column or instance method."
      end

      # Detects whether +source+'s reader on +klass+ is a user-defined
      # override (rather than AR's auto-generated reader).
      #
      # AR's auto-generated readers live in a per-class +Module+ named
      # +<ClassName>::GeneratedAttributeMethods+, +include+'d into the
      # AR class. Anything else (a user override defined directly on
      # the class, an inherited override on a parent class, or a
      # mixed-in concern Module that overrides the reader) yields a
      # different +owner+ — and is treated as a user override.
      #
      # @param klass [Class] the +Model+ class to introspect
      # @param source [Symbol, String] the source name to probe
      # @return [Boolean] +true+ when the reader is user-overridden
      #   (either on the class or via a mixed-in module / parent class);
      #   +false+ when the reader is AR-auto-generated or when no method
      #   exists by that name
      def self.user_override?(klass, source)
        return false unless klass.method_defined?(source)
        !generated_reader?(klass.instance_method(source).owner)
      end
      private_class_method :user_override?

      # The name check covers named AR classes and the duck-typed fakes
      # unit specs feed the classifier; the +is_a?+ check covers anonymous
      # AR classes, whose +GeneratedAttributeMethods+ module has a +nil+
      # name. +defined?+-guarded so the engine stays loadable without AR.
      def self.generated_reader?(owner)
        return true if owner.name.to_s.end_with?("::GeneratedAttributeMethods")
        defined?(::ActiveRecord::AttributeMethods::GeneratedAttributeMethods) &&
          owner.is_a?(::ActiveRecord::AttributeMethods::GeneratedAttributeMethods)
      end
      private_class_method :generated_reader?

      # Returns +true+ when +attribute_name+ on +model+ is backed by an
      # ActiveRecord JSON column safe for the +:wire_format+ JSON-mode emit
      # path. Recognizes +ActiveRecord::Type::Json+ and any of its subclasses
      # (notably +ConnectionAdapters::PostgreSQL::OID::Jsonb+ for
      # +t.jsonb+ columns). Sibling types — +ActiveRecord::Type::Serialized+,
      # +ActiveRecord::Encryption::EncryptedAttributeType+ — are correctly
      # rejected; they share +#type+ symbols with +Type::Json+ but do not
      # inherit from it, so the +is_a?+ check excludes them.
      #
      # Deliberately +rescue+-free. +type_for_attribute(name.to_s)+ returns
      # the +ActiveModel::Type::Value+ default (not +Type::Json+, predicate
      # returns +false+) for unknown attribute names, +nil+ inputs, or any
      # other non-resolving Source. The two ways +type_for_attribute+ raises
      # — abstract classes and tableless models — are pre-empted upstream by
      # +AccessClassifier.classify+'s +columns_hash+ access; both fail there
      # before this predicate runs. A blanket rescue would swallow real bugs
      # (typos in the predicate, AR breaking-change in a future minor) without
      # affecting the rejected cases.
      #
      # Caller contract: invoked at +Compile+ time on a Descriptor whose
      # +Models+ is a concrete, table-backed AR class.
      #
      # @param model [Class] AR model class — must respond to
      #   +#type_for_attribute+
      # @param attribute_name [Symbol, String] the +Attribute#source+ to probe
      # @return [Boolean] +true+ for +t.json+ / +t.jsonb+ columns and
      #   +Type::Json+ subclasses; +false+ otherwise
      def self.json_typed?(model, attribute_name)
        model.type_for_attribute(attribute_name.to_s).is_a?(::ActiveRecord::Type::Json)
      end

      # AR type symbols whose raw DB value is the "YYYY-MM-DD HH:MM:SS
      # [.fraction]" shape {Panko::CodeGen::DateTimeFormat} splices.
      # +:date+ / +:time+ are deliberately absent — their raw shapes are
      # different and their type-cast reads are cheap enough not to chase.
      DATETIME_TYPES = %i[datetime timestamptz].freeze

      # Returns +true+ when +attribute_name+ on +model+ is a datetime-shaped
      # column eligible for the raw-string fast path. Matches by the type's
      # +#type+ symbol rather than class so adapter-specific subclasses
      # (mysql2's +DateTime+, PG's +TimestampWithTimeZone+) all qualify;
      # custom attribute types that merely reuse the symbol also pass, which
      # is safe — their raw value fails {DateTimeFormat.format_raw}'s shape
      # checks and falls back to the type-cast read.
      #
      # @param model [Class] AR model class — must respond to
      #   +#type_for_attribute+
      # @param attribute_name [Symbol, String] the +Attribute#source+ to probe
      # @return [Boolean]
      def self.datetime_typed?(model, attribute_name)
        DATETIME_TYPES.include?(model.type_for_attribute(attribute_name.to_s).type)
      end

      # AR type symbols whose cast value comes back unchanged from the
      # +cast_datetime+ wrapper (a blanket +#as_json+ since Panko 0.8.5
      # ObjectWriter parity was restored), so Hash mode may skip the wrapper
      # for the column entirely. An allowlist — a custom attribute type with
      # an unknown symbol keeps the wrapper, since its cast value could be
      # anything. Deliberately absent, because +#as_json+ changes their cast
      # value: +:decimal+ (+BigDecimal#as_json+ is its String — 0.8.5 emitted
      # the String), +:float+ (non-finite Floats render as +nil+), +:inet+ /
      # +:cidr+ (PG casts to +IPAddr+, whose +#as_json+ is its String).
      # +:json+ / +:jsonb+ stay listed because parsed JSON holds only
      # primitives — +#as_json+ rebuilds an +==+-equal structure, so skipping
      # it changes allocations, not output.
      PLAIN_TYPES = %i[
        string text integer bigint boolean uuid binary
        json jsonb macaddr
      ].freeze

      # Returns +true+ when +attribute_name+ on +model+ is typed such that
      # the Hash-mode cast provably cannot change its value. Wrapper types
      # betray themselves via +#subtype+ while delegating the wrapped
      # column's +#type+ symbol — +Type::Serialized+ (a +serialize :col,
      # coder:+ column casts to whatever the coder round-trips) and PG's
      # +OID::Array+ (casts to a Ruby Array of element casts) — so a type
      # exposing +#subtype+ is never plain.
      #
      # @param model [Class] AR model class — must respond to
      #   +#type_for_attribute+
      # @param attribute_name [Symbol, String] the +Attribute#source+ to probe
      # @return [Boolean]
      def self.plain_typed?(model, attribute_name)
        type = model.type_for_attribute(attribute_name.to_s)
        PLAIN_TYPES.include?(type.type) && !type.respond_to?(:subtype)
      end
    end
  end
end
