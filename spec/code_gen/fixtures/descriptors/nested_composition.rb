# frozen_string_literal: true

module Fixtures
  module NestedComposition
    AUTHOR_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "NestedCompositionAuthorSerializer",
      models: nil,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :name, source: :name)
      ],
      method_attributes: [],
      associations: []
    )

    COMMENT_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "NestedCompositionCommentSerializer",
      models: nil,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :body, source: :body)
      ],
      method_attributes: [],
      associations: []
    )

    CONFIG = Panko::CodeGen::Config.new
    DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "NestedCompositionPostSerializer",
      models: nil,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id)
      ],
      method_attributes: [],
      associations: [
        Panko::CodeGen::Association.new(
          name: :author,
          kind: :has_one,
          descriptor: AUTHOR_DESCRIPTOR,
          if: ->(_record, _context) { true }
        ),
        Panko::CodeGen::Association.new(
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
