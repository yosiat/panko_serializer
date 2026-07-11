# frozen_string_literal: true

# Canonical fixture #5 in the corpus per +docs/testing.md § Canonical
# snapshot corpus+ — Folder → Item → Folder mutual cycle. Pins the
# construction-time identity-cache threading: each cyclic Generated
# Class's constructor takes a +_construct_cache:+ kwarg (default +{}+),
# registers itself in the cache before allocating nested ivars, and
# allocates each cyclic-child Generated Class via
# +(cache[d.__id__] ||= Klass.new(..., _construct_cache: cache))+ so the
# cycle terminates at construction with one Generated Class instance per
# unique Descriptor per +docs/compilation.md § Recursive Descriptors+.
#
# +FOLDER_DESCRIPTOR+ and +ITEM_DESCRIPTOR+ are constructed with empty
# +associations:+ arrays, then the mutual-referencing +Association+s
# are appended after both Descriptors exist — the standard chicken-and-
# egg idiom for recursive Descriptors per the +recursive_self+ fixture.
# Ruby +Data+ types are immutable but the Field-kind arrays are not
# frozen, so post-construction +<<+ is safe.
module Fixtures
  module RecursiveMutual
    CONFIG = Panko::CodeGen::Config.new
    FOLDER_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "RecursiveMutualFolderSerializer",
      model: nil,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :name, source: :name)
      ],
      method_attributes: [],
      associations: []
    )
    ITEM_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "RecursiveMutualItemSerializer",
      model: nil,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :name, source: :name)
      ],
      method_attributes: [],
      associations: []
    )
    FOLDER_DESCRIPTOR.associations << Panko::CodeGen::Association.new(
      name: :items, kind: :has_many, descriptor: ITEM_DESCRIPTOR
    )
    ITEM_DESCRIPTOR.associations << Panko::CodeGen::Association.new(
      name: :subfolder, kind: :has_one, descriptor: FOLDER_DESCRIPTOR
    )
    DESCRIPTOR = FOLDER_DESCRIPTOR
    MODES = %i[json hash]

    def self.sanity_record
      {
        "id" => 1,
        "name" => "root",
        "items" => [
          {
            "id" => 10,
            "name" => "item-1",
            "subfolder" => {"id" => 2, "name" => "inner", "items" => []}
          }
        ]
      }
    end

    def self.expected_output(mode)
      case mode
      when :json
        '{"id":1,"name":"root","items":[' \
          '{"id":10,"name":"item-1","subfolder":{"id":2,"name":"inner","items":[]}}' \
          "]}"
      when :hash
        {
          "id" => 1,
          "name" => "root",
          "items" => [
            {
              "id" => 10,
              "name" => "item-1",
              "subfolder" => {"id" => 2, "name" => "inner", "items" => []}
            }
          ]
        }
      end
    end
  end
end
