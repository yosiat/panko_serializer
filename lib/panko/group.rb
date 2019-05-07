# frozen_string_literal: true

module Panko
  class Group
    attr_accessor :serializer
    attr_accessor :fields

    def initialize(serializer: nil, fields: [])
      self.serializer = serializer
      self.fields     = fields
    end

    def make_filter
      {only: fields.uniq + serializer._default_attributes}
    end
  end
end
