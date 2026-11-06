# frozen_string_literal: true

require_relative "../code_gen"
require_relative "../config"
require_relative "descriptor_builder"
require_relative "instance_pool"

module Panko
  module CodeGen
    # Per-serializer-class cache of compiled Generated Classes and their Descriptor. The engine
    # keeps no cache between compile calls.
    #
    # Keyed by class identity, so a code reload (a new class object) starts empty. Reopening a
    # live serializer or record class after its first serialize is not picked up: a variant's
    # column-or-method choice for each source is fixed when it first sees the record class.
    module SerializerCache
      class Slots
        attr_accessor :compiled, :pool, :variants
      end

      class State
        attr_accessor :descriptor, :capacity_warned
        attr_reader :json, :hash

        def initialize
          @json = Slots.new
          @hash = Slots.new
        end

        def slot(output)
          case output
          when :json then @json
          when :hash then @hash
          else raise ArgumentError, "unknown output mode: #{output.inspect}"
          end
        end
      end

      # Guards the Descriptor and Slots writes and reset!. Reads skip it: under the GVL an ivar
      # read sees nil or the finished value. Not reentrant, so a locked section must not lock again.
      COMPILE_MUTEX = Mutex.new

      EMPTY_VARIANTS = {}.freeze

      def self.fetch(serializer_class, output:)
        state = serializer_class._cg_state
        compiled = state&.slot(output)&.compiled
        return compiled if compiled

        # Outside the lock: descriptor_for takes the mutex itself.
        descriptor = descriptor_for(serializer_class)

        COMPILE_MUTEX.synchronize do
          slot = state_for!(serializer_class).slot(output)
          slot.compiled ||= Panko::CodeGen.compile(descriptor, output: output, config: Config.new)
        end
      end

      def self.instance_pool(serializer_class, output)
        state = serializer_class._cg_state
        pool = state&.slot(output)&.pool
        return pool if pool

        compiled = fetch(serializer_class, output: output)
        descriptor = descriptor_for(serializer_class)

        COMPILE_MUTEX.synchronize do
          # Catches a +filters_for+ added some other way (e.g. +extend+) before the first
          # serialize. ||= never downgrades a +true+ set by the hooks.
          serializer_class._cg_has_filters_for ||= serializer_class.respond_to?(:filters_for)
          slot = state_for!(serializer_class).slot(output)
          slot.pool ||= InstancePool.new(
            :"_panko_cg_pool_#{output}_#{serializer_class.object_id}",
            compiled, descriptor
          )
        end
      end

      # Stores only compiled variants (bounded by capacity) and +CompileError+ base pins, so a
      # failing compile does not repeat on every inline-cache miss. Ineligible classes, capacity
      # overflow and other errors get the base pool with no entry, so per-call classes cannot
      # grow the map. The compile runs outside the mutex; when two threads compile the same
      # variant, the insert keeps one.
      def self.variant_pool(serializer_class, output, model)
        state = serializer_class._cg_state
        variants = state&.slot(output)&.variants
        pool = variants && variants[model]

        unless pool
          base = instance_pool(serializer_class, output)
          pool, admissible = auto_variant_pool(serializer_class, output, model, base)
          if admissible
            COMPILE_MUTEX.synchronize do
              # state_for!, not a bare _cg_state read: a reset! can land during the unlocked
              # variant compile above.
              slot = state_for!(serializer_class).slot(output)
              current = slot.variants || EMPTY_VARIANTS
              if (existing = current[model])
                pool = existing
              elsif (admitted = admit_variant(serializer_class, model, pool, base, current))
                slot.variants = current.merge(model => admitted).freeze
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

      def self.descriptor_for(serializer_class)
        state = serializer_class._cg_state
        cached = state&.descriptor
        return cached if cached

        COMPILE_MUTEX.synchronize do
          state = state_for!(serializer_class)
          state.descriptor ||=
            DescriptorBuilder.uniquify_names(DescriptorBuilder.build(serializer_class))
        end
      end

      # Clears every cache for +serializer_class+ so the next serialize rebuilds from its DSL
      # declarations. Used by tests.
      def self.reset!(serializer_class)
        COMPILE_MUTEX.synchronize do
          serializer_class._cg_state = nil
          serializer_class._cg_last_json = nil
          serializer_class._cg_last_hash = nil
          serializer_class._cg_public_descriptor = nil
          # Not nil: Serializer#descriptor reads the flag without going through instance_pool,
          # so nil would skip +filters_for+ there.
          serializer_class._cg_has_filters_for = serializer_class.respond_to?(:filters_for)
        end
      end

      # False for unseen classes and for classes pinned to the base pool.
      def self.specialized?(serializer_class, output, model)
        state = serializer_class._cg_state
        return false unless state
        slot = state.slot(output)
        pool = slot.variants && slot.variants[model]
        return false unless pool
        !pool.equal?(slot.pool)
      end

      # Includes classes pinned to the base pool.
      def self.variant_models(serializer_class, output)
        state = serializer_class._cg_state
        variants = state&.slot(output)&.variants
        variants ? variants.keys : []
      end

      # Callers must hold +COMPILE_MUTEX+: creating the State outside the lock could lose a
      # concurrent writer's cells.
      def self.state_for!(serializer_class)
        serializer_class._cg_state ||= State.new
      end
      private_class_method :state_for!

      # One frozen pair, so racing writers can never leave the model of one call with the pool
      # of another. A direct class ivar keeps the hit path at one ivar read and one compare.
      def self.remember_last(serializer_class, output, model, pool)
        pair = [model, pool].freeze
        case output
        when :json then serializer_class._cg_last_json = pair
        when :hash then serializer_class._cg_last_hash = pair
        else raise ArgumentError, "unknown output mode: #{output.inspect}"
        end
      end
      private_class_method :remember_last

      # Returns +[pool, admissible]+. Errors other than +CompileError+ can be temporary (lost
      # connection, schema not loaded), so they are not stored, and a serializer that works
      # on the Generic path never raises here.
      def self.auto_variant_pool(serializer_class, output, model, base)
        return [base, false] unless auto_specialize?(model)
        if specialized_count(serializer_class, output, base) >= Panko::Config.auto_specialization.capacity
          warn_capacity_once(serializer_class, model)
          return [base, false]
        end

        descriptor = DescriptorBuilder.uniquify_names(DescriptorBuilder.specialize(descriptor_for(serializer_class), model))
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

      # Pinned entries share the base pool object, so only non-base entries count.
      def self.specialized_count(serializer_class, output, base)
        state = serializer_class._cg_state
        variants = state&.slot(output)&.variants || EMPTY_VARIANTS
        variants.count { |_, pool| !pool.equal?(base) }
      end
      private_class_method :specialized_count

      # Runs under +COMPILE_MUTEX+ and checks capacity again, since the check in
      # {auto_variant_pool} ran without the lock. +nil+ means over capacity.
      def self.admit_variant(serializer_class, model, candidate, base, current)
        return candidate if candidate.equal?(base)
        return candidate if current.count { |_, pool| !pool.equal?(base) } < Panko::Config.auto_specialization.capacity

        warn_capacity_once(serializer_class, model)
        nil
      end
      private_class_method :admit_variant

      # Reads the State without creating it: both callers run after instance_pool built it, and
      # state_for! needs +COMPILE_MUTEX+, which one caller already holds. The flag write can race;
      # at worst the warning prints more than once.
      def self.warn_capacity_once(serializer_class, model)
        state = serializer_class._cg_state
        return if state.nil? || state.capacity_warned
        state.capacity_warned = true
        warn "#{serializer_class} auto-specialization capacity " \
          "(#{Panko::Config.auto_specialization.capacity}) reached at #{model}; " \
          "further record classes use the generic path. Raise " \
          "Panko::Config.auto_specialization.capacity if this is intentional."
      end
      private_class_method :warn_capacity_once
    end
  end
end
