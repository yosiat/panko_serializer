# frozen_string_literal: true

require_relative "hash_writer"
require_relative "plain_writer"
require_relative "active_record/writer"

module Panko::Impl
  module AttributesWriter
    def self.create(object)
      if defined?(::ActiveRecord::Base) && object.is_a?(::ActiveRecord::Base)
        return ActiveRecord::Writer.new
      end

      if object.is_a?(Hash)
        return HashWriter.new
      end

      PlainWriter.new
    end
  end
end
