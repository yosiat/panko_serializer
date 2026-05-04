# frozen_string_literal: true

require "oj"

module SerializersCodeGen
  # Per-Generated-Class fiber-local LIFO stack of +Oj::StringWriter+
  # instances reused across top-level +serialize_one+ / +serialize_many+
  # calls. Constructed once per Generated Class at +Compile+ time and
  # frozen into a class-level constant; the runtime path is +checkout+ at
  # the top of an emit + +checkin+ in +ensure+.
  #
  # Reentrancy is handled by the stack itself — a re-entrant +checkout+
  # finds the stack empty and allocates; the second-allocated Writer is
  # returned on the matching +checkin+, after which subsequent reentrant
  # calls reuse it without further allocation. Steady-state stack size
  # equals the peak observed reentrancy depth on that fiber for that
  # Generated Class; after warmup, +checkout+ allocates zero objects.
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
  # must return the per-fiber LIFO Array, lazily creating it under the
  # configured storage key. See +docs/output-modes.md § Writer
  # lifecycle+ for the integration story.
  class WritersPool
    # Returns a new pool keyed by +key+. The key is a symbol baked into
    # the emitted +POOL = WritersPool::<subclass>.new(:<key>)+ constant
    # by the Generator; making it unique per (Generated Class, Output
    # Mode) keeps two classes' stacks from cross-contaminating.
    #
    # @param key [Symbol] the storage-bucket key in +Thread.current[]+
    #   or +ActiveSupport::IsolatedExecutionState[]+
    # @return [WritersPool]
    def initialize(key)
      @key = key
    end

    # Returns a Writer ready to write into. Pops the per-fiber stack on
    # hit; allocates a fresh +Oj::StringWriter(mode: :rails)+ on miss.
    # Must be paired with a matching {#checkin} — typically via
    # +begin+ / +ensure+ at the call site so an exception in the body
    # still returns the Writer to the stack cleared.
    #
    # @return [Oj::StringWriter] a fresh-or-reused Writer with an empty
    #   buffer (a freshly-allocated Writer's buffer is empty; a popped
    #   Writer was reset on its prior {#checkin})
    def checkout
      storage.pop || Oj::StringWriter.new(mode: :rails)
    end

    # Returns +writer+ to the stack after clearing its buffer via
    # +Oj::StringWriter#reset+. Safe to call from an +ensure+ block on
    # the exception path — +reset+ unwinds any open object/array frames
    # left dangling by the failing body, so the Writer is reusable on
    # the next {#checkout}.
    #
    # @param writer [Oj::StringWriter] the Writer previously returned by
    #   {#checkout}
    # @return [Array<Oj::StringWriter>] the per-fiber stack with
    #   +writer+ pushed onto it; the return value is incidental — the
    #   contract is the side effect.
    def checkin(writer)
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

      # Returns the per-fiber LIFO stack stored under +@key+ in
      # +Thread.current[]+, lazily allocating an empty Array on first
      # access.
      #
      # @return [Array<Oj::StringWriter>] the live per-fiber stack
      def storage
        Thread.current[@key] ||= []
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

      # Returns the LIFO stack stored under +@key+ in
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
        ActiveSupport::IsolatedExecutionState[@key] ||= []
      end
    end
  end
end
