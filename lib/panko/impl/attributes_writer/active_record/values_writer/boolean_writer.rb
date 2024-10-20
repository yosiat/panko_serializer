# frozen_string_literal: true

module Panko::Impl::AttributesWriter::ActiveRecord::ValuesWriter
  class BooleanWriter
    def write(value, writer, key)
      # TODO: compare against class maybe..
      if value == true || value == false
        writer.push_value(value, key)
        return true
      end

      if value.nil?
        writer.push_value(nil, key)
        return true
      end

      if value.is_a?(String)
        return nil if value.length == 0

        is_false_value =
          value == "0" || (value == "f" || value == "F") ||
          (value.downcase == "false" || value.downcase == "off")

        writer.push_value(is_false_value ? false : true, key)
        return true
      end

      if value.is_a?(Integer)
        writer.push_value(value == 1, key)
      end

      false
    end
  end
end
