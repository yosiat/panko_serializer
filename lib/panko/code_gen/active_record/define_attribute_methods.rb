# frozen_string_literal: true

module Panko::CodeGen
  module ActiveRecord
    # Defensive idempotent wrapper around +ActiveRecord::Base.define_attribute_methods+.
    # AR generates column readers lazily on first use; the +Specialized
    # path+'s introspection (column lookup via +Model.columns_hash+ +
    # method lookup via +Model.method_defined?+) needs the method table
    # populated before classification or step (2) of the 3-step rule
    # would mis-classify column-backed Sources as missing.
    #
    # Research-backed by +docs/research/define_attribute_methods_safety.md+:
    # +define_attribute_methods+ is byte-identical across Rails 7.2 / 8.0 /
    # 8.1, idempotent (returns +false+ on the second-and-subsequent call),
    # and thread-safe via AR's +GeneratedAttributeMethods::LOCK = Monitor.new+
    # (re-entrant mutex with double-checked read). The +attribute_methods_generated?+
    # short-circuit here is an optimization on top of AR's own self-gate —
    # avoids the Monitor acquisition on the common warm path.
    #
    # Surface is one method (+.ensure!(klass)+); deliberately the deepest
    # part of S6 alongside +AccessClassifier+. If a future Rails ever
    # renames or moves the underlying method, the feature-detect switch
    # goes here — no per-Rails-version file tree per
    # +docs/structure.md § Why no per-Rails-version adapter folder+.
    module DefineAttributeMethods
      # Calls +klass.define_attribute_methods+ when the class has not yet
      # generated its column readers, otherwise returns immediately.
      # Idempotent — safe to call once per class per +Compile+, and safe
      # to call concurrently from multiple threads (AR's internal
      # +Monitor+ serializes the actual definition pass).
      #
      # @param klass [Class] the +Model+ class to populate; must respond
      #   to +#attribute_methods_generated?+ and +#define_attribute_methods+
      # @return [void]
      def self.ensure!(klass)
        return if klass.attribute_methods_generated?
        klass.define_attribute_methods
        nil
      end
    end
  end
end
