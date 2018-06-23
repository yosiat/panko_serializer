# frozen_string_literal: true

class Panko::SerializerResolver
  def self.resolve(name)
    serializer_name = "#{name.singularize.camelize}Serializer"
    serializer_const = safe_const_get(serializer_name)

    return nil if serializer_const.nil?
    return nil unless is_serializer(serializer_const)

    serializer_const
  end

  private

  def self.is_serializer(const)
    const < Panko::Serializer
  end

  def self.safe_const_get(name)
    Object.const_get(name)
  rescue NameError
    nil
  end
end
