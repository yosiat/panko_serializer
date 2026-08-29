# frozen_string_literal: true

module Panko::CodeGen
  # Formats a raw (pre-type-cast) DB datetime String as the ISO-8601 String
  # Panko's C extension emitted, without materializing a Time. AR's type
  # cast (String parse → Time → TimeWithZone) plus +#as_json+ costs an
  # order of magnitude more than splicing the already-formatted bytes: the
  # DB hands back "YYYY-MM-DD HH:MM:SS[.fraction]" — UTC whenever
  # +ActiveRecord.default_timezone+ is +:utc+, which is the caller's
  # compile-time gate — and that is the target format modulo the "T"
  # separator, millisecond truncation, and the trailing "Z".
  module DateTimeFormat
    # "YYYY-MM-DDTHH:MM:SS.mmmZ" — 24 bytes; the splices below overwrite
    # date, time, and up to three fraction digits in place.
    TEMPLATE = "0000-00-00T00:00:00.000Z"

    module_function

    # @param raw [Object] a column's +read_attribute_before_type_cast+ value
    # @return [String, nil] the ISO-8601 String, or +nil+ when +raw+ isn't
    #   a recognizable DB datetime String (a dirty attribute holding a
    #   Time, a nil column, an exotic adapter format) — callers fall back
    #   to the type-cast read.
    def format_raw(raw)
      return nil unless raw.is_a?(String)
      len = raw.bytesize
      # Already ISO-8601 UTC ("...T...Z") — some adapters normalize.
      return raw if len >= 20 && raw.getbyte(len - 1) == 90 && raw.getbyte(10) == 84
      return nil if len < 19
      return nil unless raw.getbyte(10) == 32

      out = TEMPLATE.dup
      out.bytesplice(0, 10, raw, 0, 10)
      out.bytesplice(11, 8, raw, 11, 8)
      if len > 20 && raw.getbyte(19) == 46
        # Truncate (never round) to milliseconds — same as #xmlschema(3),
        # which #as_json delegates to. Copy only the digit run: PG trims
        # trailing fraction zeros and appends its "+00" session-UTC offset
        # ("...15.5+00"), so counting from the string end would splice the
        # offset bytes in. 0.8.5's C splice copied isdigit() bytes and
        # zero-padded the same way; the template supplies the padding.
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
