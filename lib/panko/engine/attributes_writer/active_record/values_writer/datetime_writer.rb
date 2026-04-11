# frozen_string_literal: true

module Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter
  class DateTimeWriter
    # Template: "0000-00-00T00:00:00.000Z" (24 bytes)
    TEMPLATE = "0000-00-00T00:00:00.000Z"

    def initialize
      @buf = TEMPLATE.dup
    end

    def write(value, writer, key)
      return false unless value.is_a?(String)

      len = value.bytesize

      # Already ISO8601 UTC (ends with Z) - pass through
      if value.getbyte(len - 1) == 90 # Z
        writer.push_value(value, key)
        return true
      end

      # Fast path: "YYYY-MM-DD HH:MM:SS" (len=19) or with fractional
      return false if len < 19

      # Validate: space at position 10
      return false unless value.getbyte(10) == 32 # ' '

      # Reuse buffer: reset to template then splice
      result = @buf
      result.bytesplice(0, 24, TEMPLATE)

      splice_date_and_time(result, value)

      # Handle fractional seconds
      if len > 20 && value.getbyte(19) == 46 # '.'
        frac_avail = len - 20
        frac_avail = 3 if frac_avail > 3
        splice_fractional(result, value, frac_avail)
      end

      writer.push_value(result, key)
      true
    end

    # DateTime values require type-specific parsing and cannot be written
    # with a simple +push_value+ call.
    # @return [Boolean]
    def nil_safe_push?
      false
    end

    # Ruby 3.3+ supports 5-argument bytesplice (source offset + length),
    # which copies directly without allocating an intermediate string.
    # Fall back to 3-argument bytesplice + byteslice on older Rubies.
    FIVE_ARG_BYTESPLICE = begin
      "abcd".dup.bytesplice(0, 2, "xxxx", 0, 2) # rubocop:disable Performance/UnfreezeString
      true
    rescue ArgumentError
      false
    end

    private_constant :FIVE_ARG_BYTESPLICE

    if FIVE_ARG_BYTESPLICE

      def splice_date_and_time(result, value)
        result.bytesplice(0, 10, value, 0, 10)
        result.bytesplice(11, 8, value, 11, 8)
      end

      def splice_fractional(result, value, frac_avail)
        result.bytesplice(20, frac_avail, value, 20, frac_avail)
      end
    else
      def splice_date_and_time(result, value)
        result.bytesplice(0, 10, value.byteslice(0, 10))
        result.bytesplice(11, 8, value.byteslice(11, 8))
      end

      def splice_fractional(result, value, frac_avail)
        result.bytesplice(20, frac_avail, value.byteslice(20, frac_avail))
      end
    end
  end
end
