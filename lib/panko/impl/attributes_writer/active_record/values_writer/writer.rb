# frozen_string_literal: true

require_relative "string_writer"
require_relative "integer_writer"
require_relative "float_writer"
require_relative "boolean_writer"
require_relative "datetime_writer"
require_relative "json_writer"

module Panko::Impl::AttributesWriter::ActiveRecord::ValuesWriter
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

      if attribute.type.nil?
        writer.push_value(value, key)
        return
      end

      # TODO: validate against arrays
      written = case attribute.type.type
      when :string, :text, :uuid
        @string_writer.write(value, writer, key)
      when :integer
        @integer_writer.write(value, writer, key)
      when :float
        @float_writer.write(value, writer, key)
      when :boolean
        @boolean_writer.write(value, writer, key)
      when :datetime
        @date_time_writer.write(value, writer, key)
      when :json, :jsonb
        @json_writer.write(value, writer, key)
      else
        false
      end

      unless written
        writer.push_value(attribute.type.deserialize(value), key)
      end
    end
  end

  # TODO: maybe use `include Singleton` here
  @@writer = Writer.new

  def self.write(writer, attribute, value)
    @@writer.write(writer, attribute, value)
  end
end
