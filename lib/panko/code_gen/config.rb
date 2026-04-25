# frozen_string_literal: true

module SerializersCodeGen
  # Compile-time settings baked into a Generated Class. A frozen
  # +Data.define+ value with sensible defaults — most callers can omit
  # +config:+ on +SerializersCodeGen.compile+ entirely. See
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
  #
  # The two +hash_*_key_type+ fields are enum-shaped; only +:string+ and
  # +:symbol+ are accepted. Construction with any other value raises
  # +DescriptorError+ synchronously.
  Config = Data.define(
    :null_for_missing_has_one,
    :supports_root_key,
    :hash_record_key_type,
    :hash_output_key_type
  )

  # Default values applied to omitted kwargs in +Config.new+. Documented
  # in +docs/config.md § Shape+; mirrored here so +.new+ can merge them
  # before validation. Frozen to keep the constant safe to share.
  Config::DEFAULTS = {
    null_for_missing_has_one: true,
    supports_root_key: false,
    hash_record_key_type: :string,
    hash_output_key_type: :string
  }.freeze

  # Allowed values for the +hash_record_key_type+ and
  # +hash_output_key_type+ enum fields. Anything outside this set raises
  # +DescriptorError+ at +.new+.
  Config::HASH_KEY_TYPES = %i[string symbol].freeze

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
    # @raise [DescriptorError] on the first enum-field violation.
    def validate!(values)
      validate_enum!(:hash_record_key_type, values[:hash_record_key_type])
      validate_enum!(:hash_output_key_type, values[:hash_output_key_type])
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
  end

  Config.singleton_class.prepend(Config::ClassMethods)
end
