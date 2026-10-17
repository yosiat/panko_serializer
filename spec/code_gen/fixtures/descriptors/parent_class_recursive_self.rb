# frozen_string_literal: true

class ParentClassRecursiveBase
  def viewer_tag
    "viewer=#{@scope}"
  end
end

module Fixtures
  module ParentClassRecursiveSelf
    CONFIG = Panko::CodeGen::Config.new
    DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "ParentClassRecursiveSelfCommentSerializer",
      model: nil,
      parent_class: ParentClassRecursiveBase,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :body, source: :body)
      ],
      method_attributes: [
        Panko::CodeGen::MethodAttribute.new(name: :viewer_tag, body: :viewer_tag)
      ],
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

    def self.sanity_scope
      "alice"
    end

    def self.expected_output(mode)
      case mode
      when :json
        '{"id":1,"body":"root","replies":[' \
          '{"id":2,"body":"c1","replies":[],"viewer_tag":"viewer=alice"},' \
          '{"id":3,"body":"c2","replies":[],"viewer_tag":"viewer=alice"}' \
          '],"viewer_tag":"viewer=alice"}'
      when :hash
        {
          "id" => 1,
          "body" => "root",
          "replies" => [
            {"id" => 2, "body" => "c1", "replies" => [], "viewer_tag" => "viewer=alice"},
            {"id" => 3, "body" => "c2", "replies" => [], "viewer_tag" => "viewer=alice"}
          ],
          "viewer_tag" => "viewer=alice"
        }
      end
    end
  end
end
