# frozen_string_literal: true

module Panko::CodeGen
  module ActiveRecord
    # Columns read through AR's own generated reader classify as +:column+.
    # A user override of a column reader classifies as +:method+, so the
    # Specialized path never bypasses it. Call +DefineAttributeMethods.ensure!+
    # first, or non-column readers (+attribute+, +alias_attribute+) raise +UnknownSourceError+.
    module AccessClassifier
      def self.classify(klass, source)
        if klass.columns_hash.key?(source.to_s)
          return user_override?(klass, source) ? :method : :column
        end
        return :method if klass.method_defined?(source)
        raise UnknownSourceError,
          "#{klass.name}: source :#{source} is not a column or instance method."
      end

      def self.user_override?(klass, source)
        return false unless klass.method_defined?(source)
        !generated_reader?(klass.instance_method(source).owner)
      end
      private_class_method :user_override?

      # The name check matches the fake model classes the unit specs use; +is_a?+ matches real AR.
      # +defined?+ lets this run when Active Record is not loaded.
      def self.generated_reader?(owner)
        return true if owner.name.to_s.end_with?("::GeneratedAttributeMethods")
        defined?(::ActiveRecord::AttributeMethods::GeneratedAttributeMethods) &&
          owner.is_a?(::ActiveRecord::AttributeMethods::GeneratedAttributeMethods)
      end
      private_class_method :generated_reader?

      # +is_a?+ rather than the +#type+ symbol: +Type::Serialized+ and encrypted
      # attribute types share the symbol but do not inherit from +Type::Json+.
      def self.json_typed?(model, attribute_name)
        model.type_for_attribute(attribute_name.to_s).is_a?(::ActiveRecord::Type::Json)
      end

      # +:date+ / +:time+ are absent: their raw shapes differ from the
      # "YYYY-MM-DD HH:MM:SS" shape {Panko::CodeGen::DateTimeFormat} splices.
      DATETIME_TYPES = %i[datetime timestamptz].freeze

      def self.datetime_typed?(model, attribute_name)
        DATETIME_TYPES.include?(model.type_for_attribute(attribute_name.to_s).type)
      end

      # Cast values that +cast_datetime+ returns unchanged, so Hash mode may skip it.
      # +:decimal+, +:float+, +:inet+, +:cidr+ are absent: +cast_datetime+ can change their value.
      # +:json+ / +:jsonb+ are listed although +#as_json+ builds a new object: parsed JSON holds
      # only primitives, so the result is ==-equal and skipping the cast saves only allocations.
      PLAIN_TYPES = %i[
        string text integer bigint boolean uuid binary
        json jsonb macaddr
      ].freeze

      # Wrapper types (+Type::Serialized+, PG's +OID::Array+) report their +#subtype+'s +#type+
      # but cast to something else.
      def self.plain_typed?(model, attribute_name)
        type = model.type_for_attribute(attribute_name.to_s)
        PLAIN_TYPES.include?(type.type) && !type.respond_to?(:subtype)
      end
    end
  end
end
