# frozen_string_literal: true

module Panko::CodeGen
  # Compile-time settings baked into a Generated Class; omitted fields take DEFAULTS.
  #
  # - +null_for_missing_has_one+: a has_one source returning +nil+ writes +null+
  #   (+nil+ in Hash mode) instead of omitting the key.
  # - +supports_root_key+: when +false+, passing +root_key:+ raises +ArgumentError+.
  # - +json_column_emit+ (JSON mode, Specialized path only): +:wire_format+ writes the
  #   stored bytes after a well-formedness check, +:html_safe+ the typed value, escaped.
  # - +pool_writer+: no effect in Hash output mode.
  # - +guarded_model+: a record of another class goes to the generic body.
  #   Needs a named +descriptor.model+.
  Config = Data.define(
    :null_for_missing_has_one,
    :supports_root_key,
    :hash_record_key_type,
    :hash_output_key_type,
    :json_column_emit,
    :pool_writer,
    :guarded_model
  )

  Config::DEFAULTS = {
    null_for_missing_has_one: true,
    supports_root_key: false,
    hash_record_key_type: :string,
    hash_output_key_type: :string,
    json_column_emit: :wire_format,
    pool_writer: true,
    guarded_model: false
  }.freeze

  Config::HASH_KEY_TYPES = %i[string symbol].freeze

  Config::JSON_COLUMN_EMIT_MODES = %i[wire_format html_safe].freeze

  # Prepended because +Data.define+ defines +new+ on Config itself, so a
  # plain +def self.new+ would replace it and leave no +super+ to call.
  module Config::ClassMethods
    def new(**kwargs)
      merged = Config::DEFAULTS.merge(kwargs)
      validate!(merged)
      super(**merged)
    end

    private

    def validate!(values)
      validate_enum!(:hash_record_key_type, values[:hash_record_key_type])
      validate_enum!(:hash_output_key_type, values[:hash_output_key_type])
      validate_json_column_emit!(values[:json_column_emit])
      validate_boolean!(:pool_writer, values[:pool_writer])
      validate_boolean!(:guarded_model, values[:guarded_model])
    end

    def validate_enum!(field, value)
      return if Config::HASH_KEY_TYPES.include?(value)
      raise DescriptorError,
        "Config##{field}: invalid value #{value.inspect}; must be :string or :symbol."
    end

    # +ArgumentError+, not +DescriptorError+: this field picks how code is
    # written, it is not part of the Descriptor's shape.
    def validate_json_column_emit!(value)
      return if Config::JSON_COLUMN_EMIT_MODES.include?(value)
      raise ArgumentError,
        "Config#json_column_emit: invalid value #{value.inspect}; must be :wire_format or :html_safe."
    end

    def validate_boolean!(field, value)
      return if value.equal?(true) || value.equal?(false)
      raise ArgumentError,
        "Config##{field}: invalid value #{value.inspect}; must be true or false."
    end
  end

  Config.singleton_class.prepend(Config::ClassMethods)
end
