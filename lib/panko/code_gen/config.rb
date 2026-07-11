# frozen_string_literal: true

module Panko::CodeGen
  # Compile-time settings baked into a Generated Class. A frozen
  # +Data.define+ value with sensible defaults — most callers can omit
  # +config:+ on +Panko::CodeGen.compile+ entirely. See
  # +docs/config.md § Shape+ for the documented fields and defaults.
  #
  # Field defaults applied at +.new+ time:
  #
  # - +null_for_missing_has_one+: +true+ — emit +null+ / +nil+ for a
  #   +has_one+ Association whose Source returns +nil+ (rather than
  #   omitting the key).
  # - +supports_root_key+: +false+ — Generated Class methods do not accept
  #   a +root_key:+ kwarg; passing one raises +ArgumentError+ at call time.
  # - +hash_record_key_type+: +:string+ — generic-path Hash record lookup
  #   uses string keys (+record["id"]+).
  # - +hash_output_key_type+: +:string+ — Hash output mode keys are
  #   strings (+result["id"] = ...+).
  # - +json_column_emit+: +:wire_format+ — Specialized-path JSON-mode
  #   AR-JSON-column Attributes emit raw stored bytes via +push_json+
  #   after a +Oj.sc_parse+ well-formedness check; +:html_safe+ keeps
  #   today's +push_value(_read_attribute(...))+ shape (HTML-escaped).
  # - +pool_writer+: +true+ — JSON-mode +serialize_one+ /
  #   +serialize_many+ check out an +Oj::StringWriter+ from a
  #   per-Generated-Class fiber-local LIFO pool ({WritersPool}) and
  #   return it in an +ensure+ block. Setting to +false+ emits the
  #   pre-pooling source verbatim (writer allocated inline, no
  #   +begin+/+ensure+ wrap, no +POOL+ constant) — the documented
  #   rollback path. No-op for +output: :hash+ (Hash mode allocates no
  #   Writer).
  # - +guarded_model+: +false+ — Specialized-path bodies trust the
  #   caller's Model contract unconditionally. +true+ (the
  #   auto-specialization shape) prepends a per-record
  #   +record.instance_of?(<Model>)+ guard to +_write_one+ / +_to_hash+
  #   that delegates mismatched records to an inline generic twin body
  #   (+_generic_write_one+ / +_generic_to_hash+) — same fields, duck
  #   dispatch, Hash branch — so a variant compiled for one record class
  #   can never emit wrong output for another. Requires
  #   +descriptor.model+ to be a named class (the guard references it by
  #   constant path).
  #
  # The two +hash_*_key_type+ fields are enum-shaped; only +:string+ and
  # +:symbol+ are accepted. Construction with any other value raises
  # +DescriptorError+ synchronously. The +json_column_emit+ field is
  # also enum-shaped; +:wire_format+ and +:html_safe+ are the only
  # accepted values, and any other value raises +ArgumentError+ at +.new+.
  # The +pool_writer+ field is Boolean-shaped; only +true+ / +false+
  # are accepted, and any other value raises +ArgumentError+ at +.new+.
  Config = Data.define(
    :null_for_missing_has_one,
    :supports_root_key,
    :hash_record_key_type,
    :hash_output_key_type,
    :json_column_emit,
    :pool_writer,
    :guarded_model
  )

  # Default values applied to omitted kwargs in +Config.new+. Documented
  # in +docs/config.md § Shape+; mirrored here so +.new+ can merge them
  # before validation. Frozen to keep the constant safe to share.
  Config::DEFAULTS = {
    null_for_missing_has_one: true,
    supports_root_key: false,
    hash_record_key_type: :string,
    hash_output_key_type: :string,
    json_column_emit: :wire_format,
    pool_writer: true,
    guarded_model: false
  }.freeze

  # Allowed values for the +hash_record_key_type+ and
  # +hash_output_key_type+ enum fields. Anything outside this set raises
  # +DescriptorError+ at +.new+.
  Config::HASH_KEY_TYPES = %i[string symbol].freeze

  # Allowed values for +json_column_emit+. Anything outside this set
  # raises +ArgumentError+ at +.new+. See +docs/config.md+ for the
  # per-mode contract and the byte-divergence table.
  Config::JSON_COLUMN_EMIT_MODES = %i[wire_format html_safe].freeze

  # Class-method overrides prepended onto +Config+'s singleton class. The
  # prepend is required because +Data.define+'s generated +new+ is
  # defined natively on the class itself; defining +Config.new+ directly
  # would shadow it without a callable +super+. Prepending on the
  # singleton class inserts this module above the generated +new+ in
  # the lookup chain so +super+ dispatches to the original constructor.
  module Config::ClassMethods
    # Constructs a frozen Config, applying documented defaults to any
    # omitted kwarg and running structural validation on the merged
    # values before delegating to the +Data.define+-generated +new+.
    #
    # @param kwargs [Hash{Symbol => Object}] partial overrides keyed by
    #   field name; any field omitted falls back to its entry in
    #   {Config::DEFAULTS}.
    # @return [Config] frozen instance with all four documented fields
    #   populated.
    # @raise [DescriptorError] when +hash_record_key_type+ or
    #   +hash_output_key_type+ is not in {Config::HASH_KEY_TYPES}.
    # @raise [ArgumentError] when +json_column_emit+ is not in
    #   {Config::JSON_COLUMN_EMIT_MODES}.
    def new(**kwargs)
      merged = Config::DEFAULTS.merge(kwargs)
      validate!(merged)
      super(**merged)
    end

    private

    # Runs the cheap structural checks on the merged Config kwargs. Only
    # the enum-shaped fields are validated here; Boolean fields are
    # accepted as-is per +docs/config.md+.
    #
    # @param values [Hash{Symbol => Object}] the merged kwargs about to
    #   be passed to the +Data.define+-generated +new+.
    # @return [void]
    # @raise [DescriptorError] on a +hash_*_key_type+ enum violation.
    # @raise [ArgumentError] on a +json_column_emit+ enum violation.
    def validate!(values)
      validate_enum!(:hash_record_key_type, values[:hash_record_key_type])
      validate_enum!(:hash_output_key_type, values[:hash_output_key_type])
      validate_json_column_emit!(values[:json_column_emit])
      validate_boolean!(:pool_writer, values[:pool_writer])
      validate_boolean!(:guarded_model, values[:guarded_model])
    end

    # Asserts +value+ is one of the allowed enum values for +field+. On
    # violation, raises +DescriptorError+ with a message that names the
    # offending field and the observed value, per
    # +docs/errors.md § Message convention+.
    #
    # @param field [Symbol] the Config field being validated; used
    #   verbatim in the error message.
    # @param value [Object] the observed value to check against
    #   {Config::HASH_KEY_TYPES}.
    # @return [void]
    # @raise [DescriptorError] when +value+ is not in
    #   {Config::HASH_KEY_TYPES}.
    def validate_enum!(field, value)
      return if Config::HASH_KEY_TYPES.include?(value)
      raise DescriptorError,
        "Config##{field}: invalid value #{value.inspect}; must be :string or :symbol."
    end

    # Asserts +value+ is one of {Config::JSON_COLUMN_EMIT_MODES}. Unlike
    # the +hash_*_key_type+ enum, a violation here raises +ArgumentError+
    # rather than +DescriptorError+ — the field gates a code-emit shape,
    # not a Descriptor-shape, and the user-facing contract is "invalid
    # symbolic option, fix the call site" rather than "invalid Descriptor
    # input".
    #
    # @param value [Object] the observed value to check.
    # @return [void]
    # @raise [ArgumentError] when +value+ is not in
    #   {Config::JSON_COLUMN_EMIT_MODES}.
    def validate_json_column_emit!(value)
      return if Config::JSON_COLUMN_EMIT_MODES.include?(value)
      raise ArgumentError,
        "Config#json_column_emit: invalid value #{value.inspect}; must be :wire_format or :html_safe."
    end

    # Asserts +value+ is +true+ or +false+. Anything else (including
    # +nil+, a Symbol, or a truthy non-Boolean) raises +ArgumentError+.
    # Both Boolean fields gate a code-emit shape decision, not a
    # Descriptor shape, so the error class matches
    # +validate_json_column_emit!+'s convention.
    #
    # @param field [Symbol] the Config field being validated; used
    #   verbatim in the error message.
    # @param value [Object] the observed value to check.
    # @return [void]
    # @raise [ArgumentError] when +value+ is not +true+ or +false+.
    def validate_boolean!(field, value)
      return if value.equal?(true) || value.equal?(false)
      raise ArgumentError,
        "Config##{field}: invalid value #{value.inspect}; must be true or false."
    end
  end

  Config.singleton_class.prepend(Config::ClassMethods)
end
