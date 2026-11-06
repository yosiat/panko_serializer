# frozen_string_literal: true

class ParentClassSpecializedBase
  def greeting
    "Hi, #{@object.name}!"
  end
end

# +model:+ is a plain Ruby class, so the Specialized path reads attributes by method call.
class ParentClassSpecializedRecord
  attr_accessor :id, :name

  def initialize(id:, name:)
    @id = id
    @name = name
  end
end

module Fixtures
  module ParentClassSpecialized
    CONFIG = Panko::CodeGen::Config.new
    DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "ParentClassSpecializedSerializer",
      model: ParentClassSpecializedRecord,
      parent_class: ParentClassSpecializedBase,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :name, source: :name)
      ],
      method_attributes: [
        Panko::CodeGen::MethodAttribute.new(name: :greeting, body: :greeting),
        Panko::CodeGen::MethodAttribute.new(name: :static, body: -> { 42 })
      ],
      associations: []
    )
    MODES = %i[json hash]

    def self.sanity_record
      ParentClassSpecializedRecord.new(id: 1, name: "alice")
    end

    def self.expected_output(mode)
      case mode
      when :json then '{"id":1,"name":"alice","greeting":"Hi, alice!","static":42}'
      when :hash
        {"id" => 1, "name" => "alice", "greeting" => "Hi, alice!", "static" => 42}
      end
    end
  end
end
