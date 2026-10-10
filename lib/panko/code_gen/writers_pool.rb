# frozen_string_literal: true

require "oj"
require_relative "../config"

module Panko::CodeGen
  # A stack, not one writer per fiber: a nested serialize call (from a method attribute)
  # pops a different writer, or creates one when the stack is empty.
  # +Oj::StringWriter#reset+ keeps the grown buffer, so +checkin+ drops a writer
  # whose output was larger than +Panko::Config.writer_pool_max_bytes+.
  class WritersPool
    STORAGE_KEY = :_panko_writers

    def checkout
      storage.pop || Oj::StringWriter.new(mode: :rails)
    end

    # A +nil+ +result+ means the call raised; the writer is dropped then too.
    def checkin(writer, result)
      return if result.nil? || result.bytesize > Panko::Config.writer_pool_max_bytes

      writer.reset
      storage.push(writer)
    end

    private

    def storage
      raise NotImplementedError, "#{self.class} must override #storage"
    end

    # +Thread.current[]+ is fiber-local in MRI. Needs no Rails.
    class ThreadLocal < WritersPool
      private

      def storage
        Thread.current[STORAGE_KEY] ||= []
      end
    end

    # Follows ActiveRecord's connection pool: per thread, or per fiber when
    # +ActiveSupport::IsolatedExecutionState.isolation_level+ is +:fiber+.
    class IsolatedExecutionState < WritersPool
      private

      def storage
        ActiveSupport::IsolatedExecutionState[STORAGE_KEY] ||= []
      end
    end
  end
end
