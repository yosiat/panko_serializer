# frozen_string_literal: true

module Fixtures
  module ShallowSpecialized
    CONFIG = Panko::CodeGen::Config.new
    DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "ShallowSpecializedSerializer",
      models: [Post],
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :title, source: :title),
        Panko::CodeGen::Attribute.new(name: :headline, source: :headline)
      ],
      method_attributes: [
        Panko::CodeGen::MethodAttribute.new(name: :static, body: -> { 42 }),
        Panko::CodeGen::MethodAttribute.new(name: :hidden, body: ->(_record) { Panko::CodeGen::SKIP }),
        Panko::CodeGen::MethodAttribute.new(name: :contextual, body: ->(_record, context) { context })
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
