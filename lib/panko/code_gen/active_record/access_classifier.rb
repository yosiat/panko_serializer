# frozen_string_literal: true

module SerializersCodeGen
  module ActiveRecord
    # Single-class Source-classification rule for the Specialized path
    # per +docs/compilation.md § Specialized path+. Encodes the 3-step
    # rule once (column → method → raise) so the +Generator+ and the
    # +SourceResolution+ validator never duplicate it.
    #
    # Surface is one method (+.classify(klass, source)+); internals are
    # duck-typed against +klass.columns_hash+ + +klass.method_defined?+
    # so unit coverage runs against fake AR-like classes without booting
    # a real ActiveRecord stack. Multi-class intersection (STI / mixed
    # sets) is +out of scope+ here — S7 extends this module with the
    # +classify(klasses, source)+ Array form per
    # +docs/compilation.md § STI and mixed class sets+.
    module AccessClassifier
      # Classifies +source+ against +klass+ via the 3-step rule:
      #
      # 1. +source+ appears in +klass.columns_hash+ (keys are Strings) →
      #    +:column+. Column-backed wins over a same-named instance method
      #    by design — overrides are bypassed on the Specialized path per
      #    +docs/compilation.md § Overrides are bypassed+.
      # 2. else, +source+ is an instance method of +klass+ (+method_defined?+
      #    returns +true+) → +:method+.
      # 3. else → raise +UnknownSourceError+.
      #
      # Caller is responsible for ensuring AR's lazy attribute methods
      # have been generated (via +DefineAttributeMethods.ensure!+) before
      # step 2; the +SourceResolution+ validator does this.
      #
      # @param klass [Class] the +Model+ class to introspect; must respond
      #   to +#columns_hash+ (returning a Hash keyed by column-name String)
      #   and +#method_defined?+
      # @param source [Symbol, String] the +Attribute#source+ to classify;
      #   accepts either type since +columns_hash+ keys are Strings while
      #   +method_defined?+ accepts both
      # @return [Symbol] +:column+ when column-backed; +:method+ when
      #   the class exposes a same-named instance method
      # @raise [SerializersCodeGen::UnknownSourceError] when neither
      #   step (1) nor step (2) matches; message names +klass+ and +source+
      #   but does not include +Descriptor+ / +Field+ context (the
      #   +SourceResolution+ validator wraps the raise to satisfy the
      #   +docs/errors.md § Message convention+ format)
      def self.classify(klass, source)
        source_str = source.to_s
        return :column if klass.columns_hash.key?(source_str)
        return :method if klass.method_defined?(source)
        raise UnknownSourceError,
          "#{klass.name}: source :#{source_str} is not a column or instance method."
      end
    end
  end
end
