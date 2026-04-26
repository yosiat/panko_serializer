# frozen_string_literal: true

module Fixtures
  module ShallowSpecialized
    CONFIG = SerializersCodeGen::Config.new
    DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "ShallowSpecializedSerializer",
      models: [Post],
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id),
        SerializersCodeGen::Attribute.new(name: :title, source: :title),
        SerializersCodeGen::Attribute.new(name: :headline, source: :headline)
      ],
      method_attributes: [
        SerializersCodeGen::MethodAttribute.new(name: :static, body: -> { 42 }),
        SerializersCodeGen::MethodAttribute.new(name: :hidden, body: ->(_record) { SerializersCodeGen::SKIP }),
        SerializersCodeGen::MethodAttribute.new(name: :contextual, body: ->(_record, context) { context })
      ],
      associations: []
    )
    MODES = %i[json hash]

    def self.sanity_record
      Post.new(id: 1, title: "hi", body: "world", views: 7)
    end

    def self.expected_output(mode)
      case mode
      when :json then '{"id":1,"title":"hi","headline":"HI (id=1)","static":42,"contextual":null}'
      when :hash
        {
          "id" => 1,
          "title" => "hi",
          "headline" => "HI (id=1)",
          "static" => 42,
          "contextual" => nil
        }
      end
    end
  end
end
