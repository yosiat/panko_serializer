# frozen_string_literal: true

module Panko
  module CodeGen
    # Minimal writer-like object that captures the last value from a
    # +push_value+ call. Used by hash-path helpers to reuse the existing
    # cached writer / ValuesWriter pipeline without allocating an
    # ObjectWriter.
    #
    # Thread-safe: each thread gets its own instance via +.instance+.
    class ValueCapture
      # The captured value from the most recent +push_value+ call.
      # @return [Object]
      attr_reader :value

      def push_value(value, _key = nil)
        @value = value.as_json
      end

      # JSON columns call +push_json+ through the JsonWriter.
      def push_json(value, _key = nil)
        @value = if value.is_a?(String)
          begin
            Oj.load(value)
          rescue
            nil
          end
        else
          value
        end
      end

      # Returns a thread-local instance.
      #
      # @return [ValueCapture]
      def self.instance
        Thread.current[:_panko_value_capture] ||= new
      end
    end
  end
end
