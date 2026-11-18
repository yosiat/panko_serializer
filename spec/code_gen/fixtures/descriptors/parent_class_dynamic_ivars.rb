# frozen_string_literal: true

class ParentClassDynamicIvarsBase
  def greeting
    instance_variable_set(:"@greeting_#{@object["id"]}", "Hi, #{@object["name"]}!")
  end
end

module Fixtures
  module ParentClassDynamicIvars
    CONFIG = Panko::CodeGen::Config.new
    DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "ParentClassDynamicIvarsSerializer",
      model: nil,
      parent_class: ParentClassDynamicIvarsBase,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id)
      ],
      method_attributes: [
        Panko::CodeGen::MethodAttribute.new(name: :greeting, body: :greeting),
        Panko::CodeGen::MethodAttribute.new(name: :static, body: -> { 42 })
      ],
      associations: []
    )
    MODES = %i[json hash]

    def self.sanity_record
      {"id" => 1, "name" => "alice"}
    end

    def self.expected_output(mode)
      case mode
      when :json then '{"id":1,"greeting":"Hi, alice!","static":42}'
      when :hash then {"id" => 1, "greeting" => "Hi, alice!", "static" => 42}
      end
    end
  end
end
