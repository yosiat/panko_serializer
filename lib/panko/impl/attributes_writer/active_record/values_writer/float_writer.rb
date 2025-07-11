# frozen_string_literal: true

module Panko::Impl::AttributesWriter::ActiveRecord::ValuesWriter
  class FloatWriter
    def write(value, writer, key)
      if value.is_a?(Float)
        writer.push_value(value, key)
        true
      elsif value.is_a?(String)
        writer.push_value(value.to_f, key)
        true
      else
        false
      end
    end
  end
end
