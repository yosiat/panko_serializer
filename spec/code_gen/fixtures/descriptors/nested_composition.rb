# frozen_string_literal: true

module Fixtures
  module NestedComposition
    AUTHOR_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "NestedCompositionAuthorSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id),
        SerializersCodeGen::Attribute.new(name: :name, source: :name)
      ],
      method_attributes: [],
      associations: []
    )

    COMMENT_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "NestedCompositionCommentSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id),
        SerializersCodeGen::Attribute.new(name: :body, source: :body)
      ],
      method_attributes: [],
      associations: []
    )

    CONFIG = SerializersCodeGen::Config.new
    DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "NestedCompositionPostSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id)
      ],
      method_attributes: [],
      associations: [
        SerializersCodeGen::Association.new(
          name: :author,
          kind: :has_one,
          descriptor: AUTHOR_DESCRIPTOR,
          if: ->(_record, _context) { true }
        ),
        SerializersCodeGen::Association.new(
          name: :comments,
          kind: :has_many,
          descriptor: COMMENT_DESCRIPTOR
        )
      ]
    )
    MODES = %i[json hash]

    def self.sanity_record
      {
        "id" => 1,
        "author" => {"id" => 7, "name" => "alice"},
        "comments" => [
          {"id" => 11, "body" => "first"},
          {"id" => 12, "body" => "second"}
        ]
      }
    end

    def self.expected_output(mode)
      case mode
      when :json
        '{"id":1,"author":{"id":7,"name":"alice"},' \
          '"comments":[{"id":11,"body":"first"},{"id":12,"body":"second"}]}'
      when :hash
        {
          "id" => 1,
          "author" => {"id" => 7, "name" => "alice"},
          "comments" => [
            {"id" => 11, "body" => "first"},
            {"id" => 12, "body" => "second"}
          ]
        }
      end
    end
  end
end
