# frozen_string_literal: true

# The associations are appended after both Descriptors exist, since each refers to the other.
module Fixtures
  module RecursiveMutual
    CONFIG = Panko::CodeGen::Config.new
    FOLDER_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "RecursiveMutualFolderSerializer",
      model: nil,
      parent_class: Fixtures::BaseSerializer,
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
      parent_class: Fixtures::BaseSerializer,
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
