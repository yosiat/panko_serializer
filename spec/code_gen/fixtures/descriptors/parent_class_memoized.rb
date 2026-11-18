# frozen_string_literal: true

class ParentClassMemoizedBase
  def greeting
    @greeting ||= "Hi, #{@object["name"]}!"
  end

  def nickname
    return @nickname if defined?(@nickname)
    @nickname = @object["name"].upcase
  end
end

module Fixtures
  module ParentClassMemoized
    CONFIG = Panko::CodeGen::Config.new
    DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "ParentClassMemoizedSerializer",
      model: nil,
      parent_class: ParentClassMemoizedBase,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id)
      ],
      method_attributes: [
        Panko::CodeGen::MethodAttribute.new(name: :greeting, body: :greeting),
        Panko::CodeGen::MethodAttribute.new(name: :nickname, body: :nickname)
      ],
      associations: []
    )
    MODES = %i[json hash]

    def self.sanity_record
      {"id" => 1, "name" => "alice"}
    end

    def self.expected_output(mode)
      case mode
      when :json then '{"id":1,"greeting":"Hi, alice!","nickname":"ALICE"}'
      when :hash then {"id" => 1, "greeting" => "Hi, alice!", "nickname" => "ALICE"}
      end
    end
  end
end
