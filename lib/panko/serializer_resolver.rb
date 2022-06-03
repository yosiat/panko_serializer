# frozen_string_literal: true

require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/module/introspection'

class Panko::SerializerResolver
  class << self
    def resolve(name, from)
      serializer_const = nil

      if namespace = namespace_for(from)
        serializer_const = safe_serializer_get("#{namespace}::#{name.singularize.camelize}Serializer")
      end

      serializer_const ||= safe_serializer_get("#{name.singularize.camelize}Serializer")
      serializer_const ||= safe_serializer_get(name)
      serializer_const
    end

    private

    if Module.method_defined?(:module_parent_name)
      def namespace_for(from)
        from.module_parent_name
      end
    else
      def namespace_for(from)
        from.parent_name
      end
    end

    def safe_serializer_get(name)
      const = Object.const_get(name)
      const < Panko::Serializer ? const : nil
    rescue NameError
      nil
    end
  end
end
