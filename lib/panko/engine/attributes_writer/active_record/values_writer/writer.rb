# frozen_string_literal: true

require_relative "string_writer"
require_relative "integer_writer"
require_relative "float_writer"
require_relative "boolean_writer"
require_relative "datetime_writer"
require_relative "json_writer"
require_relative "subtype_writer"

module Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter
  # Type Casting
  #
  # We do "special" type casting which is mix of two inspirations:
  #  *) light records gem
  #  *) pg TextDecoders
  #
  # The whole idea behind those type casts, are to do the minimum required
  # type casting in the most performant manner and *allocation free*.
  #
  # For example, in `ActiveRecord::Type::String` the type_cast_from_database
  # creates new string, for known reasons, but, in serialization flow we don't
  # need to create new string becuase we afraid of mutations.
  #
  # Since we know before hand, that we are only reading from the database, and
  # *not* writing and the end result if for JSON we can skip some "defenses".
  class Writer
    def initialize
      @string_writer = StringWriter.new
      @integer_writer = IntegerWriter.new
      @float_writer = FloatWriter.new
      @boolean_writer = BooleanWriter.new
      @date_time_writer = DateTimeWriter.new
      @json_writer = JsonWriter.new
    end

    def write(writer, attribute, value)
      key = attribute.name_for_serialization

      if value.nil?
        writer.push_value(nil, key)
        return
      end

      # Fast path: use cached writer (covers most calls after first pass)
      cached = attribute.cached_writer
      if cached
        unless cached.write(value, writer, key)
          writer.push_value(attribute.type.deserialize(value), key)
        end
        return
      end

      type = attribute.type

      if type.nil?
        writer.push_value(value, key)
        return
      end

      if type.respond_to?(:subtype)
        subtype_writer = SubtypeWriter.new(type)
        attribute.cached_writer = subtype_writer
        subtype_writer.write(value, writer, key)
        return
      end

      # First time: resolve writer by type and cache it
      type_writer = resolve_writer(type.type)

      if type_writer
        attribute.cached_writer = type_writer
        unless type_writer.write(value, writer, key)
          writer.push_value(type.deserialize(value), key)
        end
      else
        writer.push_value(type.deserialize(value), key)
      end
    end

    private

    def resolve_writer(type_sym)
      case type_sym
      when :string, :text, :uuid
        @string_writer
      when :integer
        @integer_writer
      when :float
        @float_writer
      when :boolean
        @boolean_writer
      when :datetime
        @date_time_writer
      when :json, :jsonb
        @json_writer
      end
    end
  end

  # Each thread gets its own Writer instance so the mutable
  # DateTimeWriter buffer is never shared across Puma workers.
  def self.write(writer, attribute, value)
    w = Thread.current[:panko_values_writer] ||= Writer.new
    w.write(writer, attribute, value)
  end
end
