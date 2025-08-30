# frozen_string_literal: true

module Panko
  class Attribute < Data.define(:name, :alias_name, :name_sym, :name_str, :ivar_name, :type, :record_class)
    def self.create(name, alias_name: nil)
      name_str = name.to_s.freeze
      alias_name_str = alias_name&.to_s&.freeze
      name_sym = name.to_sym
      ivar_name = "@#{name_str}".freeze

      new(
        name: name_str,
        alias_name: alias_name_str,
        name_sym: name_sym,
        name_str: name_str,
        ivar_name: ivar_name,
        type: nil,
        record_class: nil
      )
    end

    def ==(other)
      return name_sym == other if other.is_a? Symbol
      return name == other.name && alias_name == other.alias_name if other.is_a? Panko::Attribute
      super
    end

    def hash
      name_sym.hash
    end

    def eql?(other)
      self.==(other)
    end

    def inspect
      "<Panko::Attribute name=#{name.inspect} alias_name=#{alias_name.inspect}>"
    end

    # Get the name to use for serialization (alias if present, otherwise name)
    def serialization_name
      alias_name || name
    end

    # Resolve ActiveRecord alias attributes by checking the record class
    # This mirrors the C extension's attribute_try_invalidate function
    def resolve_activerecord_alias(new_record_class)
      return self if record_class == new_record_class

      # Check if this record class has attribute aliases
      if new_record_class.respond_to?(:attribute_aliases)
        ar_aliases_hash = new_record_class.attribute_aliases

        unless ar_aliases_hash.empty?
          aliased_value = ar_aliases_hash[name]
          if aliased_value
            # Create a new attribute with the resolved name
            # The original name becomes the alias_name, and the resolved name becomes name
            return Attribute.new(
              name: aliased_value.freeze,
              alias_name: name,
              name_sym: aliased_value.to_sym,
              name_str: aliased_value.freeze,
              ivar_name: "@#{aliased_value}".freeze,
              type: type,
              record_class: new_record_class
            )
          end
        end
      end

      # Return a copy with updated record_class but same attributes
      Attribute.new(
        name: name,
        alias_name: alias_name,
        name_sym: name_sym,
        name_str: name_str,
        ivar_name: ivar_name,
        type: type,
        record_class: new_record_class
      )
    end
  end
end
