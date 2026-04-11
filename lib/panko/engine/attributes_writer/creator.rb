# frozen_string_literal: true

require_relative "hash_writer"
require_relative "plain_writer"
require_relative "active_record/writer"

module Panko::Engine
  module AttributesWriter
    # Returns the writer class appropriate for +object+ without instantiating.
    #
    # @param object [Object] the object to inspect
    # @return [Class] the writer class
    def self.writer_for(object)
      if defined?(::ActiveRecord::Base) && object.is_a?(::ActiveRecord::Base)
        return ActiveRecord::Writer
      end

      if object.is_a?(Hash)
        return HashWriter
      end

      PlainWriter
    end

    # Creates a new writer instance appropriate for +object+.
    #
    # @param object [Object] the object to inspect
    # @return [ActiveRecord::Writer, HashWriter, PlainWriter]
    def self.create(object)
      writer_for(object).new
    end
  end
end
