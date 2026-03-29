# frozen_string_literal: true

module Panko::Impl::AttributesWriter::ActiveRecord::ValuesWriter
  class DateTimeWriter
    # Template: "0000-00-00T00:00:00.000Z" (24 bytes)
    TEMPLATE = "0000-00-00T00:00:00.000Z"

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

      # Build result: dup template, splice date and time directly from source
      result = TEMPLATE.dup

      # Copy "YYYY-MM-DD" (10 bytes) - zero-alloc splice from source
      result.bytesplice(0, 10, value, 0, 10)
      # Copy "HH:MM:SS" (8 bytes) - zero-alloc splice from source
      result.bytesplice(11, 8, value, 11, 8)

      # Handle fractional seconds
      if len > 20 && value.getbyte(19) == 46 # '.'
        frac_avail = len - 20
        frac_avail = 3 if frac_avail > 3
        result.bytesplice(20, frac_avail, value, 20, frac_avail)
      end

      writer.push_value(result, key)
      true
    end
  end
end
