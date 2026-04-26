# frozen_string_literal: true

module SerializersCodeGen
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
      #    for all) → +:column+. The fast path that bypasses any
      #    user-defined reader override per +docs/compilation.md §
      #    Overrides are bypassed+.
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
      # Caller is responsible for ensuring AR's lazy attribute methods
      # have been generated (via +DefineAttributeMethods.ensure!+) on
      # every class in +klasses+ before classification; the
      # +SourceResolution+ validator does this.
      #
      # @param klasses [Array<Class>] one-or-more +Model+ classes to
      #   introspect; each must respond to +#columns_hash+ (returning a
      #   Hash keyed by column-name String) and +#method_defined?+
      # @param source [Symbol, String] the +Attribute#source+ to classify;
      #   accepts either type since +columns_hash+ keys are Strings while
      #   +method_defined?+ accepts both
      # @return [Symbol] +:column+ when uniformly column-backed across
      #   every class; +:method+ when uniformly resolvable as a method
      #   (even if some classes have a column with the same name)
      # @raise [SerializersCodeGen::UnknownSourceError] when at least one
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

        return :column if verdicts.all?(:column)
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
    end
  end
end
