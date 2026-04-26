# frozen_string_literal: true

module Fixtures
  module NestedComposition
    AUTHOR_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "AuthorSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id),
        SerializersCodeGen::Attribute.new(name: :name, source: :name)
      ],
      method_attributes: [],
      associations: []
    )

    CONFIG = SerializersCodeGen::Config.new
    DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "PostSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id)
      ],
      method_attributes: [],
      associations: [
        SerializersCodeGen::Association.new(
          name: :author,
          kind: :has_one,
          descriptor: AUTHOR_DESCRIPTOR
        )
      ]
    )
    MODES = %i[json hash]

    def self.sanity_record
      {"id" => 1, "author" => {"id" => 7, "name" => "alice"}}
    end

    def self.expected_output(mode)
      case mode
      when :json then '{"id":1,"author":{"id":7,"name":"alice"}}'
      when :hash then {"id" => 1, "author" => {"id" => 7, "name" => "alice"}}
      end
    end
  end
end
