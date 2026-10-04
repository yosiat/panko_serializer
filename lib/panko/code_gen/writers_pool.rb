# frozen_string_literal: true

require "oj"
require_relative "../config"

module Panko::CodeGen
  # Fiber-local LIFO stack of +Oj::StringWriter+ instances reused across
  # top-level +serialize_one+ / +serialize_many+ calls. Every Generated
  # Class shares the one stack: a writer only lives for the length of a
  # call, so which class used it last does not matter. Each Generated
  # Class holds a pool object in a +POOL+ constant; the runtime path is
  # +checkout+ at the top of an emit + +checkin+ in +ensure+.
  #
  # Reentrancy is handled by the stack itself: a re-entrant +checkout+
  # finds the stack empty and allocates, and the matching +checkin+
  # returns the second Writer. Steady-state stack size equals the peak
  # reentrancy depth seen on that fiber.
  #
  # +Oj::StringWriter#reset+ rewinds the cursor but keeps the grown
  # buffer, so +checkin+ drops a Writer whose output was larger than
  # +Panko::Config.writer_pool_max_bytes+. A kept Writer therefore holds
  # less than twice that limit (the buffer grows by doubling).
  #
  # Two storage backends are exposed as subclasses, picked by the
  # Generator at +Compile+ time:
  #
  # - {WritersPool::ThreadLocal} — uses +Thread.current[]+, which is
  #   fiber-local in MRI (+thread.c:3812+) and ships with no Rails
  #   dependency. The default for non-Rails consumers.
  # - {WritersPool::IsolatedExecutionState} — uses
  #   +ActiveSupport::IsolatedExecutionState+, aligning the pool's
  #   locality with AR ConnectionPool's locality on Rails 7.0+.
  #
  # The base class is abstract: callers always instantiate one of the
  # subclasses. The +storage+ method is the only extension point — it
  # must return the per-fiber LIFO Array stored under {STORAGE_KEY}.
  class WritersPool
    # The one +Thread.current[]+ / +ActiveSupport::IsolatedExecutionState[]+
    # key every pool reads, so all Generated Classes share a stack.
    STORAGE_KEY = :_panko_writers

    # Returns a Writer ready to write into. Pops the per-fiber stack on
    # hit; allocates a fresh +Oj::StringWriter(mode: :rails)+ on miss.
    # Must be paired with a matching {#checkin} — typically via
    # +begin+ / +ensure+ at the call site.
    #
    # @return [Oj::StringWriter] a fresh-or-reused Writer with an empty
    #   buffer (a freshly-allocated Writer's buffer is empty; a popped
    #   Writer was reset on its prior {#checkin})
    def checkout
      storage.pop || Oj::StringWriter.new(mode: :rails)
    end

    # Returns +writer+ to the stack, cleared via +Oj::StringWriter#reset+,
    # when +result+ is at most +Panko::Config.writer_pool_max_bytes+.
    # Otherwise drops it so the GC frees its buffer: a +result+ over the
    # limit (a large response), or +nil+ (the body raised before
    # producing one).
    #
    # @param writer [Oj::StringWriter] the Writer previously returned by
    #   {#checkout}
    # @param result [String, nil] the JSON the call produced
    # @return [void]
    def checkin(writer, result)
      return if result.nil? || result.bytesize > Panko::Config.writer_pool_max_bytes

      writer.reset
      storage.push(writer)
    end

    private

    # Per-fiber LIFO stack of pooled Writers, lazily initialized to an
    # empty Array on first access. Subclasses override to pick the
    # storage backend; the base implementation raises so a misconfigured
    # direct +WritersPool.new+ surfaces loudly.
    #
    # @return [Array<Oj::StringWriter>] the live stack — mutating the
    #   returned Array mutates the pool's storage
    # @raise [NotImplementedError] when called on the abstract base
    #   class instead of a subclass
    def storage
      raise NotImplementedError, "#{self.class} must override #storage"
    end

    # Pool variant backed by +Thread.current[]+. Per MRI +thread.c:3812+
    # ("Thread#[] and Thread#[]= are not thread-local but fiber-local"),
    # each Fiber + main thread has its own slot, so two Fibers in the
    # same thread do not collide on the pooled Writer. No Rails
    # dependency — the default for non-Rails consumers and for any
    # consumer running on Rails < 7.0.
    class ThreadLocal < WritersPool
      private

      # Returns the per-fiber LIFO stack stored under {STORAGE_KEY} in
      # +Thread.current[]+, lazily allocating an empty Array on first
      # access.
      #
      # @return [Array<Oj::StringWriter>] the live per-fiber stack
      def storage
        Thread.current[STORAGE_KEY] ||= []
      end
    end

    # Pool variant backed by +ActiveSupport::IsolatedExecutionState+.
    # Aligns the pool's locality with AR ConnectionPool's locality on
    # Rails 7.0+ — under Puma the locality is per-thread; under Falcon
    # (where +ActiveSupport::IsolatedExecutionState.isolation_level+ is
    # set to +:fiber+) it is per-fiber. The +ActiveSupport+ constant is
    # referenced only inside +#storage+, so this class is loadable in
    # bundles without ActiveSupport — a misconfigured instantiation in
    # a non-Rails environment does not raise until +checkout+ /
    # +checkin+ is called.
    class IsolatedExecutionState < WritersPool
      private

      # Returns the LIFO stack stored under {STORAGE_KEY} in
      # +ActiveSupport::IsolatedExecutionState[]+, lazily allocating an
      # empty Array on first access. Locality (per-thread vs per-fiber)
      # follows whatever +AS::IES.isolation_level+ is set to.
      #
      # @return [Array<Oj::StringWriter>] the live per-context stack
      # @raise [NameError] when +ActiveSupport::IsolatedExecutionState+
      #   is not loaded — the class is meant to be selected at +Compile+
      #   time only when +defined?(ActiveSupport::IsolatedExecutionState)+
      #   is truthy.
      def storage
        ActiveSupport::IsolatedExecutionState[STORAGE_KEY] ||= []
      end
    end
  end
end
