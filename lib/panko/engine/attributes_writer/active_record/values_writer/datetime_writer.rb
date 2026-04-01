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

      # Copy "YYYY-MM-DD" (10 bytes) and "HH:MM:SS" (8 bytes).
      # Use the 3-argument bytesplice for Ruby 3.2 compatibility — the
      # 5-argument form (zero-alloc source range) was added in Ruby 3.3.
      result.bytesplice(0, 10, value.byteslice(0, 10))
      result.bytesplice(11, 8, value.byteslice(11, 8))

      # Handle fractional seconds
      if len > 20 && value.getbyte(19) == 46 # '.'
        frac_avail = len - 20
        frac_avail = 3 if frac_avail > 3
        result.bytesplice(20, frac_avail, value.byteslice(20, frac_avail))
      end

      writer.push_value(result, key)
      true
    end
  end
end
