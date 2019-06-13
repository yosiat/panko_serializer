# frozen_string_literal: true

module Panko
  class Group
    attr_accessor :serializer
    attr_accessor :fields
    attr_accessor :block

    def initialize(serializer: nil, fields: [], block: ->{})
      self.serializer = serializer
      self.fields     = fields
      self.block      = block
    end

    def make_filter
      {only: fields.uniq + serializer._default_attributes}
    end
  end
end
