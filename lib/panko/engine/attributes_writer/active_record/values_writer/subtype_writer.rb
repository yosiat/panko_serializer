# frozen_string_literal: true

module Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter
  # Handles ActiveRecord types that wrap another type (e.g. +ActiveRecord::Type::Serialized+).
  # These types respond to +#subtype+ and require full +#deserialize+ to produce
  # the correct Ruby value — no fast-path shortcut is possible.
  #
  # @example
  #   # A model with `serialize :data, coder: JSON` produces a Serialized type
  #   # whose #deserialize parses the JSON string into a Ruby Hash/Array.
  class SubtypeWriter
    # @param type [ActiveModel::Type::Value] an AR type that responds to +#subtype+
    def initialize(type)
      @type = type
    end

    # Deserializes +value+ through the wrapped type and pushes the result.
    #
    # @param value [Object] the raw database value
    # @param writer [Oj::StringWriter] the JSON output target
    # @param key [String] the JSON key
    # @return [true] always handled
    def write(value, writer, key)
      writer.push_value(@type.deserialize(value), key)
      true
    end

    # @return [Boolean] false — nil must be checked by the caller
    def nil_safe_push?
      false
    end
  end
end
