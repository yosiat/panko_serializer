# frozen_string_literal: true

module Panko::CodeGen
  # Formats a raw DB datetime String ("YYYY-MM-DD HH:MM:SS[.fraction]") as ISO-8601 without
  # building a Time. Used only when +ActiveRecord.default_timezone+ is +:utc+, so the value is UTC.
  module DateTimeFormat
    TEMPLATE = "0000-00-00T00:00:00.000Z"

    module_function

    # Returns +nil+ when +raw+ is not a DB datetime String (a dirty attribute holding
    # a Time, a nil column, another adapter format); callers then use the type-cast read.
    def format_raw(raw)
      return nil unless raw.is_a?(String)
      len = raw.bytesize
      # Some adapters already return ISO-8601 UTC ("...T...Z").
      return raw if len >= 20 && raw.getbyte(len - 1) == 90 && raw.getbyte(10) == 84
      return nil if len < 19
      return nil unless raw.getbyte(10) == 32

      out = TEMPLATE.dup
      out.bytesplice(0, 10, raw, 0, 10)
      out.bytesplice(11, 8, raw, 11, 8)
      if len > 20 && raw.getbyte(19) == 46
        # Truncate (never round) to milliseconds, like +#xmlschema(3)+. Copy only the
        # digits: PG trims trailing zeros and appends "+00" ("...15.5+00").
        fraction_digits = 0
        while fraction_digits < 3
          byte = raw.getbyte(20 + fraction_digits)
          break if byte.nil? || byte < 48 || byte > 57
          fraction_digits += 1
        end
        out.bytesplice(20, fraction_digits, raw, 20, fraction_digits) if fraction_digits > 0
      end
      out
    end
  end
end
