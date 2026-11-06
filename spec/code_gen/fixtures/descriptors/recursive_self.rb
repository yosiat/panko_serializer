# frozen_string_literal: true

# The association is appended after the Descriptor exists, since it refers to itself.
module Fixtures
  module RecursiveSelf
    CONFIG = Panko::CodeGen::Config.new
    DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "RecursiveSelfCommentSerializer",
      model: nil,
      parent_class: Fixtures::BaseSerializer,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :body, source: :body)
      ],
      method_attributes: [],
      associations: []
    )
    DESCRIPTOR.associations << Panko::CodeGen::Association.new(
      name: :replies,
      kind: :has_many,
      descriptor: DESCRIPTOR
    )
    MODES = %i[json hash]

    def self.sanity_record
      {
        "id" => 1,
        "body" => "root",
        "replies" => [
          {"id" => 2, "body" => "c1", "replies" => []},
          {"id" => 3, "body" => "c2", "replies" => []}
        ]
      }
    end

    def self.expected_output(mode)
      case mode
      when :json
        '{"id":1,"body":"root","replies":[' \
          '{"id":2,"body":"c1","replies":[]},' \
          '{"id":3,"body":"c2","replies":[]}' \
          "]}"
      when :hash
        {
          "id" => 1,
          "body" => "root",
          "replies" => [
            {"id" => 2, "body" => "c1", "replies" => []},
            {"id" => 3, "body" => "c2", "replies" => []}
          ]
        }
      end
    end
  end
end
