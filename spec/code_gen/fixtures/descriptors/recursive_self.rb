# frozen_string_literal: true

# Canonical fixture #4 in the corpus per +docs/testing.md § Canonical
# snapshot corpus+ — +Comment has_many :replies+ → same +CommentDescriptor+.
# Pins the self-recursion shortcut: the constructor of the Generated
# Class assigns +@replies_serializer = self+ instead of allocating a
# nested instance, breaking the otherwise-infinite +.new+ chain at
# construction time per +docs/compilation.md § Recursive Descriptors+.
#
# +DESCRIPTOR+ is constructed with an empty +associations:+ array, then
# the self-referencing +Association+ is appended after the Descriptor
# exists — Ruby +Data+ types are immutable but the Field-kind arrays
# are not frozen, so post-construction +<<+ is safe and is the standard
# idiom for self-recursive Descriptors (mirror of the technique pinned
# in +spec/validators/callable_arity_spec.rb+'s self-recursion it).
module Fixtures
  module RecursiveSelf
    CONFIG = Panko::CodeGen::Config.new
    DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "RecursiveSelfCommentSerializer",
      model: nil,
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
