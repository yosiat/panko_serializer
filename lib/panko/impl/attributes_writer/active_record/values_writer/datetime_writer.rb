# frozen_string_literal: true

module Panko::Impl::AttributesWriter::ActiveRecord::ValuesWriter
  class DateTimeWriter
    def write(value, writer, key)
      # The actual implementation is in the native extension
      # if there is no native extension, we will fallback to Rails implementation
      false
    end
  end
end
