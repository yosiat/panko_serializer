# frozen_string_literal: true

require_relative "../code_gen"
require_relative "../config"
require_relative "descriptor_builder"
require_relative "instance_pool"

module Panko
  module CodeGen
    # Per-serializer-class cache of compiled Generated Classes, plus the
    # (mode-agnostic) converted Descriptor. This is the caller-side cache
    # the engine deliberately does not keep
    # (docs/merging-into-panko.md § Compile cache stays in Panko).
    #
    # Two tiers per (serializer class, mode):
    #
    # - the **base** Generated Class / {InstancePool} — Generic record
    #   access — held in a class ivar, compiled once, read lock-free.
    # - the **auto-specialization variant map** ({variant_pool}) — a frozen
    #   copy-on-write Hash of record class → {InstancePool}, grown at first
    #   sight of each record class. Eligible AR classes get a guarded
    #   Specialized variant compiled for them; everything else (Hash
    #   records, POROs, anonymous/non-AR classes, compile failures,
    #   capacity overflow) is pinned to the base pool so lookup stays
    #   uniform. Reads never lock — the map is replaced wholesale
    #   (GVL-atomic ivar swap of a frozen Hash) under +COMPILE_MUTEX+.
    #   Capacity comes from +Panko::Config.auto_specialization+; overflow
    #   pins to base and warns once per serializer class.
    #
    # The converted Descriptor is cached too and shared between compile and
    # instantiation: a Generated Class with associations reads
    # +descriptor.associations+ in its constructor to build child serializers,
    # so +.new(descriptor:)+ must receive the same Descriptor it was compiled
    # from. Auto variants get their own +descriptor.with(model:)+ twin,
    # carried by their pool the same way.
    #
    # Keyed by class identity: a Rails/Zeitwerk reload mints a new class object
    # with an empty cache, so edits self-heal. Manually reopening a live class
    # after its first serialize is unsupported (documented limitation).
    #
    # Config is fixed at compile time to the engine defaults, which reproduce
    # Panko 0.8.5's output (string hash keys, :wire_format JSON columns,
    # pooled writer); auto variants additionally set +guarded_model+ so a
    # mismatched record delegates to the inline generic twin instead of
    # producing wrong output.
    module SerializerCache
      # Guards the rare compile/convert miss. Reads never take it — a class-ivar
      # read (through the serializer's accessor) is atomic under the GVL, so a
      # concurrent writer is observed as either nil or the finished value, never
      # a half-built one.
      COMPILE_MUTEX = Mutex.new

      # @param serializer_class [Class] a Panko::Serializer subclass
      # @param output [Symbol] :json or :hash
      # @return [Class] the compiled Generated Class for that (class, mode)
      def self.fetch(serializer_class, output:)
        compiled = compiled_slot(serializer_class, output)
        return compiled if compiled

        # Convert outside the compile lock (it takes the lock itself); the two
        # acquisitions are sequential, never re-entrant.
        descriptor = descriptor_for(serializer_class)

        COMPILE_MUTEX.synchronize do
          compiled = compiled_slot(serializer_class, output)
          return compiled if compiled

          compiled = Panko::CodeGen.compile(descriptor, output: output, config: Config.new)
          store_compiled(serializer_class, output, compiled)
          compiled
        end
      end

      # Returns the {InstancePool} handing out Generated Class instances
      # for (serializer class, mode) — the slot the inlined serialize entry
      # points in +Panko::Serializer+ / +Panko::ArraySerializer+ check
      # instances out of. Compiles on first use. The pool's storage key
      # embeds the serializer class's object id: unique per live class
      # (Ruby never reuses object ids), and a Zeitwerk reload (new class
      # object) naturally keys a fresh slot.
      #
      # @param serializer_class [Class] a Panko::Serializer subclass
      # @param output [Symbol] :json or :hash
      # @return [Panko::CodeGen::InstancePool]
      def self.instance_pool(serializer_class, output)
        pool = pool_slot(serializer_class, output)
        return pool if pool

        compiled = fetch(serializer_class, output: output)
        descriptor = descriptor_for(serializer_class)

        COMPILE_MUTEX.synchronize do
          # Reinforces the inherited/singleton_method_added bookkeeping for a
          # +filters_for+ acquired some other way (e.g. +extend+) before the
          # first serialize. ||= so a hook-set +true+ is never downgraded.
          serializer_class._cg_has_filters_for ||= serializer_class.respond_to?(:filters_for)
          pool_slot(serializer_class, output) || store_pool(
            serializer_class, output,
            InstancePool.new(
              :"_panko_cg_pool_#{output}_#{serializer_class.object_id}",
              compiled, descriptor
            )
          )
        end
      end

      # Frozen empty variant map — the pre-first-sight state of the
      # copy-on-write per-mode variant Hash.
      EMPTY_VARIANTS = {}.freeze

      # Returns the {InstancePool} for (serializer class, mode, record
      # class) — the auto-specialization dispatch behind the seams' inline
      # cache. First sight of an eligible AR record class compiles a
      # guarded Specialized variant for it and stores it in the map.
      #
      # The map only ever grows with ADMITTED entries — specialized
      # variants (capacity-bounded) and deterministic +CompileError+ pins
      # (bounded by real AR classes; stored so a failing descriptor isn't
      # recompiled on every inline-cache miss). Everything else —
      # ineligible classes (Hash, POROs, unresolvable names), capacity
      # overflow, transient compile errors — returns the base pool WITHOUT
      # inserting, so per-call-minted record classes can't grow the map or
      # be pinned against GC; they cost their cheap eligibility re-check
      # on each inline-cache miss instead.
      #
      # The variant compile runs outside +COMPILE_MUTEX+ (mirroring
      # {fetch}'s convert-outside-the-lock discipline and avoiding
      # re-entrant locking through {instance_pool}); a concurrent first
      # sight can compile the same variant twice, and the map insert under
      # the mutex keeps exactly one — the loser's class is garbage.
      #
      # @param serializer_class [Class] a Panko::Serializer subclass
      # @param output [Symbol] :json or :hash
      # @param model [Class] the record's class (any class — non-AR uses
      #   the base pool)
      # @return [Panko::CodeGen::InstancePool]
      def self.variant_pool(serializer_class, output, model)
        variants = variants_slot(serializer_class, output)
        pool = variants && variants[model]

        unless pool
          base = instance_pool(serializer_class, output)
          pool, admissible = auto_variant_pool(serializer_class, output, model, base)
          if admissible
            COMPILE_MUTEX.synchronize do
              current = variants_slot(serializer_class, output) || EMPTY_VARIANTS
              if (existing = current[model])
                pool = existing
              elsif (admitted = admit_variant(serializer_class, model, pool, base, current))
                store_variants(serializer_class, output, current.merge(model => admitted).freeze)
                pool = admitted
              else
                pool = base
              end
            end
          end
        end

        remember_last(serializer_class, output, model, pool)
        pool
      end

      # @param serializer_class [Class] a Panko::Serializer subclass
      # @return [Panko::CodeGen::Descriptor] the converted, cached Descriptor
      def self.descriptor_for(serializer_class)
        cached = serializer_class._cg_descriptor
        return cached if cached

        COMPILE_MUTEX.synchronize do
          serializer_class._cg_descriptor ||=
            DescriptorBuilder.uniquify_names(DescriptorBuilder.build(serializer_class))
        end
      end

      # Reads/writes the per-mode compiled-class slot through the serializer
      # class's own accessor — a direct class-ivar access, no reflection.
      def self.compiled_slot(serializer_class, output)
        case output
        when :json then serializer_class._cg_compiled_json
        when :hash then serializer_class._cg_compiled_hash
        else raise ArgumentError, "unknown output mode: #{output.inspect}"
        end
      end
      private_class_method :compiled_slot

      def self.store_compiled(serializer_class, output, compiled)
        case output
        when :json then serializer_class._cg_compiled_json = compiled
        when :hash then serializer_class._cg_compiled_hash = compiled
        else raise ArgumentError, "unknown output mode: #{output.inspect}"
        end
      end
      private_class_method :store_compiled

      def self.pool_slot(serializer_class, output)
        case output
        when :json then serializer_class._cg_pool_json
        when :hash then serializer_class._cg_pool_hash
        else raise ArgumentError, "unknown output mode: #{output.inspect}"
        end
      end
      private_class_method :pool_slot

      def self.store_pool(serializer_class, output, pool)
        case output
        when :json then serializer_class._cg_pool_json = pool
        when :hash then serializer_class._cg_pool_hash = pool
        else raise ArgumentError, "unknown output mode: #{output.inspect}"
        end
      end
      private_class_method :store_pool

      def self.variants_slot(serializer_class, output)
        case output
        when :json then serializer_class._cg_variants_json
        when :hash then serializer_class._cg_variants_hash
        else raise ArgumentError, "unknown output mode: #{output.inspect}"
        end
      end
      private_class_method :variants_slot

      def self.store_variants(serializer_class, output, variants)
        case output
        when :json then serializer_class._cg_variants_json = variants
        when :hash then serializer_class._cg_variants_hash = variants
        else raise ArgumentError, "unknown output mode: #{output.inspect}"
        end
      end
      private_class_method :store_variants

      # Refreshes the seam's one-entry inline cache. The (model, pool)
      # pair lives in a single frozen Array so the swap is one GVL-atomic
      # ivar write — concurrent writers can lose the race but can never
      # produce a torn (model from A, pool from B) state.
      def self.remember_last(serializer_class, output, model, pool)
        pair = [model, pool].freeze
        case output
        when :json then serializer_class._cg_last_json = pair
        when :hash then serializer_class._cg_last_hash = pair
        else raise ArgumentError, "unknown output mode: #{output.inspect}"
        end
      end
      private_class_method :remember_last

      # Resolves the pool candidate for a first-seen +model+ and whether
      # it may be stored: +[pool, admissible]+. Admissible entries are the
      # compiled variant and the +CompileError+ base pin (deterministic
      # failure — storing it avoids recompiling on every inline-cache
      # miss). Everything else returns +[base, false]+: ineligible
      # classes, capacity overflow (pre-checked lock-free here, re-checked
      # in {admit_variant}), and non-deterministic +StandardError+ from AR
      # introspection (possibly transient — connection loss, schema not
      # loaded — so left unstored for a natural retry on a later miss;
      # auto-specialization must never turn a serializer that works
      # generically into a raise). The descriptor tree is rebuilt by
      # {DescriptorBuilder.specialize}: the root gets +model+ and each
      # association's reflected AR class fills its child's Model
      # recursively, so nested serializers get the typed emits too.
      def self.auto_variant_pool(serializer_class, output, model, base)
        return [base, false] unless auto_specialize?(model)
        if specialized_count(serializer_class, output, base) >= Panko::Config.auto_specialization.capacity
          warn_capacity_once(serializer_class, model)
          return [base, false]
        end

        descriptor = DescriptorBuilder.specialize(descriptor_for(serializer_class), model)
        compiled = Panko::CodeGen.compile(descriptor, output: output, config: Config.new(guarded_model: true))
        pool = InstancePool.new(
          :"_panko_cg_pool_#{output}_#{serializer_class.object_id}_#{model.object_id}",
          compiled, descriptor
        )
        [pool, true]
      rescue CompileError
        [base, true]
      rescue
        [base, false]
      end
      private_class_method :auto_variant_pool

      def self.auto_specialize?(model)
        Panko::Config.auto_specialization.enabled &&
          model.respond_to?(:columns_hash) &&
          model.respond_to?(:attribute_methods_generated?) &&
          DescriptorBuilder.resolvable_name?(model)
      end
      private_class_method :auto_specialize?

      # Pinned entries share the base pool object, so "not the base" is
      # what counts against capacity.
      def self.specialized_count(serializer_class, output, base)
        variants = variants_slot(serializer_class, output) || EMPTY_VARIANTS
        variants.count { |_, pool| !pool.equal?(base) }
      end
      private_class_method :specialized_count

      # Runs under +COMPILE_MUTEX+. Re-checks capacity against the current
      # map (the pre-compile check in {auto_variant_pool} was lock-free).
      # Returns the pool to store, or +nil+ for an over-capacity candidate
      # — the class then uses the base pool WITHOUT a map entry, keeping
      # the map bounded by admitted entries only.
      def self.admit_variant(serializer_class, model, candidate, base, current)
        return candidate if candidate.equal?(base)
        return candidate if current.count { |_, pool| !pool.equal?(base) } < Panko::Config.auto_specialization.capacity

        warn_capacity_once(serializer_class, model)
        nil
      end
      private_class_method :admit_variant

      # The flag write races benignly across threads — at worst the message
      # prints twice; it can never be dropped for a class that hit capacity.
      def self.warn_capacity_once(serializer_class, model)
        return if serializer_class._cg_capacity_warned
        serializer_class._cg_capacity_warned = true
        warn "#{serializer_class} auto-specialization capacity " \
          "(#{Panko::Config.auto_specialization.capacity}) reached at #{model}; " \
          "further record classes use the generic path. Raise " \
          "Panko::Config.auto_specialization.capacity if this is intentional."
      end
      private_class_method :warn_capacity_once
    end
  end
end
