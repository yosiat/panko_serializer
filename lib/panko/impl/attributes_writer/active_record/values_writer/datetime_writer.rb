# frozen_string_literal: true

module Panko::Impl::AttributesWriter::ActiveRecord::ValuesWriter
  class DateTimeWriter
    # Template: "0000-00-00T00:00:00.000Z" (24 bytes)
    TEMPLATE = "0000-00-00T00:00:00.000Z"

    # Byte constants
    Z_BYTE = 90  # 'Z'
    DASH = 45    # '-'
    SPACE = 32   # ' '
    COLON = 58   # ':'
    DOT = 46     # '.'
    ZERO = 48    # '0'
    NINE = 57    # '9'

    def write(value, writer, key)
      return false unless value.is_a?(String)

      len = value.bytesize

      # Already ISO8601 UTC (ends with Z) - pass through
      if value.getbyte(len - 1) == Z_BYTE
        writer.push_value(value, key)
        return true
      end

      # Fast path: "YYYY-MM-DD HH:MM:SS" (len=19) or "YYYY-MM-DD HH:MM:SS.n+" (len>19)
      return false if len < 19

      # Validate format: YYYY-MM-DD HH:MM:SS
      return false unless value.getbyte(4) == DASH &&
        value.getbyte(7) == DASH &&
        value.getbyte(10) == SPACE &&
        value.getbyte(13) == COLON &&
        value.getbyte(16) == COLON

      # Single allocation: dup template and overwrite bytes
      result = TEMPLATE.dup

      # Copy date bytes (YYYY-MM-DD)
      result.setbyte(0, value.getbyte(0))
      result.setbyte(1, value.getbyte(1))
      result.setbyte(2, value.getbyte(2))
      result.setbyte(3, value.getbyte(3))
      result.setbyte(5, value.getbyte(5))
      result.setbyte(6, value.getbyte(6))
      result.setbyte(8, value.getbyte(8))
      result.setbyte(9, value.getbyte(9))

      # Copy time bytes (HH:MM:SS)
      result.setbyte(11, value.getbyte(11))
      result.setbyte(12, value.getbyte(12))
      result.setbyte(14, value.getbyte(14))
      result.setbyte(15, value.getbyte(15))
      result.setbyte(17, value.getbyte(17))
      result.setbyte(18, value.getbyte(18))

      # Handle fractional seconds (positions 20-22 in result)
      if len > 20 && value.getbyte(19) == DOT
        b = value.getbyte(20)
        result.setbyte(20, b) if b >= ZERO && b <= NINE
        if len > 21
          b = value.getbyte(21)
          result.setbyte(21, b) if b >= ZERO && b <= NINE
          if len > 22
            b = value.getbyte(22)
            result.setbyte(22, b) if b >= ZERO && b <= NINE
          end
        end
      end
      # Template already has '.000Z' for no-fractional case

      writer.push_value(result, key)
      true
    end
  end
end
