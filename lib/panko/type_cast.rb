# frozen_string_literal: true

module Panko
  module TypeCast
    # Cache ActiveRecord type classes for performance
    @ar_string_type = nil
    @ar_text_type = nil
    @ar_float_type = nil
    @ar_integer_type = nil
    @ar_boolean_type = nil
    @ar_date_time_type = nil
    @ar_json_type = nil
    @ar_time_zone_converter = nil

    # PostgreSQL specific types
    @ar_pg_uuid_type = nil
    @ar_pg_json_type = nil
    @ar_pg_jsonb_type = nil

    class << self
      def type_cast(type_metadata, value)
        return value if value.nil?

        cache_type_classes
        type_klass = type_metadata.class

        # Try specific type casting first
        if string_or_text_type?(type_klass)
          cast_string_or_text_type(value)
        elsif integer_type?(type_klass)
          cast_integer_type(value)
        elsif float_type?(type_klass)
          cast_float_type(value)
        elsif boolean_type?(type_klass)
          cast_boolean_type(value)
        elsif date_time_type?(type_klass)
          cast_date_time_type(value)
        elsif json_type?(type_klass)
          cast_json_type(value)
        else
          # Fallback to ActiveRecord's deserialize method
          type_metadata.deserialize(value)
        end
      end

      # Main cast method that matches the C extension interface
      # @param type_metadata [Object] ActiveRecord type metadata
      # @param value [Object] Value to cast
      # @return [Array] [casted_value, is_json] tuple
      def cast(type_metadata, value)
        return [value, false] if value.nil?

        # Check if this is a JSON type
        is_json = json_type?(type_metadata.class)

        if is_json
          # For JSON types, return the original value with is_json flag
          [value, true]
        else
          # Cast the value using type casting logic
          casted_value = type_cast(type_metadata, value)
          [casted_value, false]
        end
      end

      private

      def cache_type_classes
        return if @ar_string_type

        @ar_string_type = ActiveRecord::Type::String
        @ar_text_type = ActiveRecord::Type::Text
        @ar_float_type = ActiveRecord::Type::Float
        @ar_integer_type = ActiveRecord::Type::Integer
        @ar_boolean_type = ActiveRecord::Type::Boolean
        @ar_date_time_type = ActiveRecord::Type::DateTime
        @ar_json_type = ActiveRecord::Type::Json if defined?(ActiveRecord::Type::Json)
        @ar_time_zone_converter = ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter if defined?(ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter)

        # PostgreSQL types
        if defined?(ActiveRecord::ConnectionAdapters::PostgreSQL)
          @ar_pg_uuid_type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Uuid if defined?(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Uuid)
          @ar_pg_json_type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Json if defined?(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Json)
          @ar_pg_jsonb_type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb if defined?(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb)
        end
      end

      def string_or_text_type?(type_klass)
        type_klass == @ar_string_type ||
          type_klass == @ar_text_type ||
          (@ar_pg_uuid_type && type_klass == @ar_pg_uuid_type)
      end

      def integer_type?(type_klass)
        type_klass == @ar_integer_type
      end

      def float_type?(type_klass)
        type_klass == @ar_float_type
      end

      def boolean_type?(type_klass)
        type_klass == @ar_boolean_type
      end

      def date_time_type?(type_klass)
        type_klass == @ar_date_time_type ||
          (@ar_time_zone_converter && type_klass == @ar_time_zone_converter)
      end

      def json_type?(type_klass)
        (@ar_json_type && type_klass == @ar_json_type) ||
          (@ar_pg_json_type && type_klass == @ar_pg_json_type) ||
          (@ar_pg_jsonb_type && type_klass == @ar_pg_jsonb_type)
      end

      def cast_string_or_text_type(value)
        return value if value.is_a?(String)
        return "t" if value == true
        return "f" if value == false

        value.to_s
      end

      def cast_integer_type(value)
        return value if value.is_a?(Integer)
        return nil if value.is_a?(String) && value.empty?
        return value.to_i if value.is_a?(Float)
        return 1 if value == true
        return 0 if value == false
        return value.to_i if value.is_a?(String)

        # Arrays, hashes, etc. should return nil
        return nil unless value.respond_to?(:to_i)

        nil
      end

      def cast_float_type(value)
        return value if value.is_a?(Float)
        return value.to_f if value.is_a?(String) && !value.empty?

        nil
      end

      def cast_boolean_type(value)
        return nil if value.nil? || (value.is_a?(String) && value.empty?)
        return true if value == true
        return false if value == false
        return true if value == 1
        return false if value == 0

        if value.is_a?(String)
          case value.downcase
          when "t", "true", "1"
            true
          when "f", "false", "0"
            false
          end
        end
      end

      def cast_date_time_type(value)
        return value unless value.is_a?(String)

        # Try to convert using TimeConversion module
        TimeConversion.convert_time_string(value)
      end

      def cast_json_type(value)
        return nil if value.nil? || (value.is_a?(String) && value.empty?)
        return value unless value.is_a?(String)

        # For JSON types, we return the string as-is if it's valid JSON
        # The actual JSON parsing will be handled by the serializer
        begin
          JSON.parse(value)
          value
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
