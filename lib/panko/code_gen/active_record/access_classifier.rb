# frozen_string_literal: true

module Panko::CodeGen
  module ActiveRecord
    # Multi-class intersection Source-classification rule for the
    # Specialized path per +docs/compilation.md § STI and mixed class sets+.
    # Encodes the intersection rule once (column-in-all → +:column+;
    # method-in-all → +:method+; else raise) so the +Generator+ and the
    # +SourceResolution+ validator never duplicate it.
    #
    # Surface is one method (+.classify(klasses, source)+); internals are
    # duck-typed against +klass.columns_hash+ + +klass.method_defined?+
    # so unit coverage runs against fake AR-like classes without booting
    # a real ActiveRecord stack. The single-class case is degenerate —
    # callers pass a 1-element Array, and the intersection of a 1-element
    # set is the element itself.
    module AccessClassifier
      # Classifies +source+ against every class in +klasses+ and returns
      # the intersection verdict per +docs/compilation.md § STI and mixed
      # class sets+:
      #
      # 1. Column-backed in every class (+source+ in +klass.columns_hash+
      #    for all) AND no user override on any class (multi-class only)
      #    → +:column+. The fast path that bypasses any user-defined
      #    reader override per +docs/compilation.md § Overrides are
      #    bypassed+.
      # 2. Else, instance method on every class (+klass.method_defined?+
      #    returns +true+ for all, even if some classes also have a
      #    column with the same name) → +:method+. This is the symmetric
      #    "any non-uniformity downgrades" rule — a subclass that
      #    overrides a column reader downgrades the Attribute across the
      #    whole Generated Class so the override is honored on every
      #    instance.
      # 3. Else (at least one class has neither a column nor an instance
      #    method by +source+'s name) → raise +UnknownSourceError+.
      #
      # Override-detection (step 1's "no user override on any class"
      # qualifier) activates only for multi-class sets (+klasses.size > 1+).
      # The single-class case explicitly preserves
      # +docs/compilation.md § Overrides are bypassed for column-backed
      # attributes+: a 1-element +klasses+ Array with a column-backed
      # source returns +:column+ even when the user has defined a
      # reader override. The asymmetry is intentional — single-class
      # callers opt into bypass semantics by passing
      # +models: [SingleClass]+; multi-class STI callers expect
      # symmetric behavior across instances of every class in the set.
      #
      # Caller is responsible for ensuring AR's lazy attribute methods
      # have been generated (via +DefineAttributeMethods.ensure!+) on
      # every class in +klasses+ before classification; the
      # +SourceResolution+ validator does this. Without
      # +define_attribute_methods+ called first, +method_defined?+
      # returns +false+ for column-name methods and the override-detection
      # cannot distinguish auto-generated readers from user overrides.
      #
      # @param klasses [Array<Class>] one-or-more +Model+ classes to
      #   introspect; each must respond to +#columns_hash+ (returning a
      #   Hash keyed by column-name String) and +#method_defined?+. For
      #   multi-class override-detection, also +#instance_method+
      #   (returning a +UnboundMethod+-like object whose +#owner+ is the
      #   defining +Module+ or +Class+).
      # @param source [Symbol, String] the +Attribute#source+ to classify;
      #   accepts either type since +columns_hash+ keys are Strings while
      #   +method_defined?+ accepts both
      # @return [Symbol] +:column+ when uniformly column-backed across
      #   every class with no user override (multi-class) or column-backed
      #   on the single class (single-class); +:method+ when uniformly
      #   resolvable as a method, when any class lacks the column-backing,
      #   or when any class user-overrides the reader (multi-class)
      # @raise [Panko::CodeGen::UnknownSourceError] when at least one
      #   class lacks both a column and an instance method by +source+'s
      #   name; message names each offending class and the +source+ but
      #   does not include +Descriptor+ / +Field+ context (the
      #   +SourceResolution+ validator wraps the raise to satisfy the
      #   +docs/errors.md § Message convention+ format)
      def self.classify(klasses, source)
        source_str = source.to_s
        verdicts = klasses.map { |klass| classify_one(klass, source, source_str) }

        missing_klasses = klasses.each_with_index.filter_map { |klass, i| klass if verdicts[i] == :missing }
        unless missing_klasses.empty?
          names = missing_klasses.map(&:name).join(", ")
          raise UnknownSourceError,
            "#{names}: source :#{source_str} is not a column or instance method."
        end

        if verdicts.all?(:column)
          return :method if klasses.size > 1 && klasses.any? { |klass| user_override?(klass, source) }
          return :column
        end
        :method
      end

      # Per-class step of the intersection rule. Returns +:column+,
      # +:method+, or +:missing+ — never raises. The aggregator in
      # +.classify+ inspects the per-class verdicts to compute the
      # intersection and raises a single +UnknownSourceError+ naming
      # every missing class.
      #
      # Column-backed wins over a same-named method at the per-class
      # level (matches the per-class single-class rule from S6.1) — but
      # the aggregator downgrades the whole intersection to +:method+
      # whenever any class lacks uniform column-backing.
      #
      # @param klass [Class] one of the classes from +.classify+
      # @param source [Symbol, String] the source name
      # @param source_str [String] +source+ pre-stringified for the
      #   +columns_hash+ lookup (avoids re-coercing per class)
      # @return [Symbol] +:column+, +:method+, or +:missing+
      def self.classify_one(klass, source, source_str)
        return :column if klass.columns_hash.key?(source_str)
        return :method if klass.method_defined?(source)
        :missing
      end
      private_class_method :classify_one

      # Detects whether +source+'s reader on +klass+ is a user-defined
      # override (rather than AR's auto-generated reader). Only consulted
      # by +.classify+ for multi-class sets — single-class sets bypass
      # this check by design (see +.classify+'s asymmetry note).
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
        owner = klass.instance_method(source).owner
        !owner.name.to_s.end_with?("::GeneratedAttributeMethods")
      end
      private_class_method :user_override?

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

      # AR type symbols whose cast values can never be datetime objects, so
      # Hash mode may skip the +cast_datetime+ wrapper for the column
      # entirely. An allowlist rather than "not datetime" — a custom
      # attribute type with an unknown symbol keeps the wrapper, since its
      # cast value could be anything.
      PLAIN_TYPES = %i[
        string text integer bigint float decimal boolean uuid binary
        json jsonb inet cidr macaddr
      ].freeze

      # Returns +true+ when +attribute_name+ on +model+ is typed such that
      # its cast value is provably not a datetime.
      #
      # @param model [Class] AR model class — must respond to
      #   +#type_for_attribute+
      # @param attribute_name [Symbol, String] the +Attribute#source+ to probe
      # @return [Boolean]
      def self.plain_typed?(model, attribute_name)
        PLAIN_TYPES.include?(model.type_for_attribute(attribute_name.to_s).type)
      end
    end
  end
end
