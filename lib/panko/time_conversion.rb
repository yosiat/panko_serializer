# frozen_string_literal: true

module Panko
  module TimeConversion
    # ActiveRecord datetime pattern: YYYY-MM-DD HH:MM:SS.microseconds
    AR_DATETIME_PATTERN = /\A(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?\z/

    class << self
      def convert_time_string(value)
        return value unless value.is_a?(String)
        return nil if value.empty?

        # Try ActiveRecord datetime format first (most common)
        if (match = AR_DATETIME_PATTERN.match(value))
          convert_ar_datetime_string(match)
        else
          # For other formats, try Ruby's built-in Time.parse
          begin
            Time.parse(value).utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
          rescue ArgumentError
            # If parsing fails, return original value
            value
          end
        end
      end

      private

      def convert_ar_datetime_string(match)
        year, month, day, hour, minute, second, microseconds = match.captures

        # Pad microseconds to 3 digits (milliseconds)
        milliseconds = if microseconds
          # Truncate or pad to 3 digits
          microseconds.ljust(6, "0")[0, 3]
        else
          "000"
        end

        # Format as ISO8601 with Z timezone
        "#{year}-#{month}-#{day}T#{hour}:#{minute}:#{second}.#{milliseconds}Z"
      end
    end
  end
end
