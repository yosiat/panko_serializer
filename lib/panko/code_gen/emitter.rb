# frozen_string_literal: true

require_relative "emitter/active_record_attributes"
require_relative "emitter/object_attributes"
require_relative "emitter/method_fields"
require_relative "emitter/associations"

module Panko
  module CodeGen
    # Source string builder for generated serializer methods.
    #
    # Provides methods for each per-attribute code pattern. The {Compiler}
    # creates an Emitter, calls pattern methods for each attribute, and
    # retrieves the assembled source via {#to_source}.
    #
    # Never called at runtime — only during class compilation.
    #
    # Emit methods are organized by concern in separate modules:
    # - {ActiveRecordAttributes} — indexed cached, first-pass, fallback paths
    # - {ObjectAttributes} — Hash and PORO attribute reads
    # - {MethodFields} — serializer method field calls
    # - {Associations} — has_one and has_many writes
    class Emitter
      include ActiveRecordAttributes
      include ObjectAttributes
      include MethodFields
      include Associations

      def initialize
        @lines = []
      end

      # Appends a raw source line.
      #
      # @param line [String] a line of Ruby source
      # @return [void]
      def <<(line)
        @lines << line
      end

      # Returns the assembled Ruby source string.
      #
      # @return [String]
      def to_source
        @lines.join("\n")
      end
    end
  end
end
