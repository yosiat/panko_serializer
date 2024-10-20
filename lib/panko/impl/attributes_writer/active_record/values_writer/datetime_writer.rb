# frozen_string_literal: true

module Panko::Impl::AttributesWriter::ActiveRecord::ValuesWriter
  class DateTimeWriter
    def write(value, writer, key)
      return false unless value.is_a?(String)

      if value.end_with?("Z") && Panko.is_iso8601_time_string(value)
        writer.push_value(value, key)
        return true
      end

      iso8601_string = Panko.iso_ar_iso_datetime_string(value)
      unless iso8601_string.nil?
        writer.push_value(iso8601_string, key)
        return true
      end

      false
    end
  end
end
