# frozen_string_literal: true

require "panko/version"
require "panko/attribute"
require "panko/association"
require "panko/serializer"
require "panko/array_serializer"
require "panko/response"
require "panko/serializer_resolver"
require "panko/object_writer"

require "oj"
if ENV["PANKO_PURE_RUBY"] == "true"
  # Temporary stubs - will be implemented in Phase 4
  module Panko
    def self.serialize_object(object, writer, descriptor)
      raise NotImplementedError, "Pure Ruby serialization not yet implemented"
    end

    def self.serialize_objects(objects, writer, descriptor)
      raise NotImplementedError, "Pure Ruby serialization not yet implemented"
    end
  end
else
  require "panko/panko_serializer"
end
