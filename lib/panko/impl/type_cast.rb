module Panko::Impl
  UNDEF = Object.new

  class TypeCast
    @@to_s_id = nil
    @@to_i_id = nil

    # Caching ActiveRecord Types
    @@ar_string_type = nil
    @@ar_text_type = nil
    @@ar_float_type = nil
    @@ar_integer_type = nil
    @@ar_boolean_type = nil
    @@ar_date_time_type = nil
    @@ar_json_type = nil
    @@ar_pg_integer_type = nil
    @@ar_pg_float_type = nil
    @@ar_pg_uuid_type = nil
    @@ar_pg_json_type = nil
    @@ar_pg_jsonb_type = nil
    @@ar_pg_array_type = nil
    @@ar_pg_date_time_type = nil
    @@ar_pg_timestamp_type = nil

    @@initialized = false

    def self.cache_postgres_type_lookup
      ar_connection_adapters = ActiveRecord::ConnectionAdapters if defined?(ActiveRecord::ConnectionAdapters)

      return false unless ar_connection_adapters

      case ActiveRecord::Base.connection.adapter_name
      when "PostgreSQL"
        adapter_module = ar_connection_adapters::PostgreSQL if defined?(ar_connection_adapters::PostgreSQL)
        return false unless adapter_module

        ar_oid = adapter_module::OID if defined?(adapter_module::OID)
        return false unless ar_oid

        @@ar_pg_float_type = ar_oid::Float if defined?(ar_oid::Float)
        @@ar_pg_integer_type = ar_oid::Integer if defined?(ar_oid::Integer)
        @@ar_pg_uuid_type = ar_oid::Uuid if defined?(ar_oid::Uuid)
        @@ar_pg_json_type = ar_oid::Json if defined?(ar_oid::Json)
        @@ar_pg_jsonb_type = ar_oid::Jsonb if defined?(ar_oid::Jsonb)
        @@ar_pg_date_time_type = ar_oid::DateTime if defined?(ar_oid::DateTime)
        @@ar_pg_timestamp_type = ar_oid::Timestamp if defined?(ar_oid::Timestamp)
      when "SQLite"
        adapter_module = ar_connection_adapters::SQLite3Adapter if defined?(ar_connection_adapters::SQLite3Adapter)
        return false unless adapter_module

        @@ar_pg_integer_type = adapter_module::SQLite3Integer if defined?(adapter_module::SQLite3Integer)
      end

      true
    end

    def self.cache_type_lookup
      return if @@initialized

      @@initialized = true

      if defined?(ActiveRecord::Type)
        @@ar_string_type = ActiveRecord::Type::String if defined?(ActiveRecord::Type::String)
        @@ar_text_type = ActiveRecord::Type::Text if defined?(ActiveRecord::Type::Text)
        @@ar_float_type = ActiveRecord::Type::Float if defined?(ActiveRecord::Type::Float)
        @@ar_integer_type = ActiveRecord::Type::Integer if defined?(ActiveRecord::Type::Integer)
        @@ar_boolean_type = ActiveRecord::Type::Boolean if defined?(ActiveRecord::Type::Boolean)
        @@ar_date_time_type = ActiveRecord::Type::DateTime if defined?(ActiveRecord::Type::DateTime)

        @@ar_json_type = ActiveRecord::Type::Json if defined?(ActiveRecord::Type::Json)
      end

      begin
        cache_postgres_type_lookup
      rescue
        # TODO: add to some debug log
      end
    end

    def self.is_string_or_text_type(type_klass)
      type_klass == @@ar_string_type || type_klass == @@ar_text_type ||
        (@@ar_pg_uuid_type && type_klass == @@ar_pg_uuid_type)
    end

    def self.cast_string_or_text_type(value)
      return value if value.is_a?(String)
      return "t" if value == true
      return "f" if value == false

      value.to_s
    end

    def self.is_float_type(type_klass)
      type_klass == @@ar_float_type || (@@ar_pg_float_type && type_klass == @@ar_pg_float_type)
    end

    def self.cast_float_type(value)
      return value if value.is_a?(Float)
      return value.to_f if value.is_a?(String)

      UNDEF
    end

    def self.is_integer_type(type_klass)
      type_klass == @@ar_integer_type || (@@ar_pg_integer_type && type_klass == @@ar_pg_integer_type)
    end

    def self.cast_integer_type(value)
      return value if value.is_a?(Integer)
      return value.to_i if value.is_a?(String) && !value.empty?
      return value.to_i if value.is_a?(Float)
      return 1 if value == true
      return 0 if value == false

      # At this point, we handled integer, float, string and booleans
      # any thing other than this (array, hashes, etc) should result in nil
      nil
    end

    def self.is_json_type(type_klass)
      @@ar_pg_json_type && type_klass == @@ar_pg_json_type ||
        @@ar_pg_jsonb_type && type_klass == @@ar_pg_jsonb_type ||
        @@ar_json_type && type_klass == @@ar_json_type
    end

    def self.is_json_value(value)
      return value unless value.is_a?(String)

      return false if value.length == 0

      begin
        result = Oj.sc_parse(Object.new, value)

        return true if result.nil?
        return false if result == false
      rescue Oj::ParseError
        return false
      end

      false
    end

    def self.is_boolean_type(type_klass)
      type_klass == @@ar_boolean_type
    end

    def self.cast_boolean_type(value)
      return value if value == true || value == false
      return nil if value.nil?

      if value.is_a?(String)
        return nil if value.length == 0

        is_false_value =
          value == "0" || (value == "f" || value == "F") ||
          (value.downcase == "false" || value.downcase == "off")

        return is_false_value ? false : true
      end

      if value.is_a?(Integer)
        return value == 1
      end

      UNDEF
    end

    def self.is_date_time_type(type_klass)
      type_klass == @@ar_date_time_type ||
        type_klass == @@ar_pg_date_time_type ||
        type_klass == @@ar_pg_timestamp_type
    end

    def self.cast_date_time_type(value)
      if value.is_a?(String)
        return value if value.end_with?("Z") && Panko.is_iso8601_time_string(value) # TODO: Implement `is_iso8601_time_string`
        iso8601_string = Panko.iso_ar_iso_datetime_string(value) # TODO: Implement `iso_ar_iso_datetime_string`
        return iso8601_string unless iso8601_string.nil?
      end

      UNDEF
    end

    def self.public_type_cast(type_metadata, value, is_json = false)
      return value if value.nil?

      cache_type_lookup

      type_klass = type_metadata.class
      type_casted_value = nil

      if is_string_or_text_type(type_klass)
        type_casted_value = cast_string_or_text_type(value)
      elsif is_integer_type(type_klass)
        type_casted_value = cast_integer_type(value)
      elsif is_boolean_type(type_klass)
        type_casted_value = cast_boolean_type(value)
      elsif is_date_time_type(type_klass)
        type_casted_value = cast_date_time_type(value)
      elsif is_float_type(type_klass)
        type_casted_value = cast_float_type(value)
      end

      if is_json_type(type_klass)
        return nil if is_json_value(value) == false
        return value
      end

      if type_casted_value == UNDEF
        return type_metadata.deserialize(value)
      end

      type_casted_value
    end
  end
end
