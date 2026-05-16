# frozen_string_literal: true

# Canonical S18 fixture for the Specialized-path parent_class shape per
# the parent S18 PRD (#95). Pins the +emit_class+ parent-swap line
# (+class <Name>_<Mode> < <parent_class.name>+), the per-record
# +@object+ / +@context+ / +@scope+ ivar writes prepended to the single
# +_write_one+ / +_to_hash+ body (Specialized has no Hash/Object
# dispatcher), and Symbol-body / Callable-body coexistence in one
# +Descriptor+. +models: [ParentClassSpecializedRecord]+ — a plain Ruby
# class (non-AR), so the Specialized path's per-Attribute access form
# falls through to method dispatch per
# +docs/compilation.md § Non-AR class in `models`+; the snapshot pins
# the +record.id+ / +record.name+ shape rather than the
# +_read_attribute(...)+ shape, which is irrelevant to the parent_class
# axis under test.
class ParentClassSpecializedBase
  # The Symbol-body Method Attribute +:greeting+ dispatches here via
  # direct method dispatch on +self+. Reads +@object+ — set by the
  # per-record ivar writes prepended to +_write_one+ / +_to_hash+ in
  # the Specialized record-access emitter.
  #
  # @return [String]
  def greeting
    "Hi, #{@object.name}!"
  end
end

# Plain Ruby record class — non-AR; the Specialized path's
# +json_column_attribute?+ / +AccessClassifier.classify+ both short-
# circuit on the empty AR subset and the per-Attribute emit downgrades
# to +record.<source>+ method dispatch.
class ParentClassSpecializedRecord
  attr_accessor :id, :name

  def initialize(id:, name:)
    @id = id
    @name = name
  end
end

module Fixtures
  module ParentClassSpecialized
    CONFIG = SerializersCodeGen::Config.new
    DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "ParentClassSpecializedSerializer",
      models: [ParentClassSpecializedRecord],
      parent_class: ParentClassSpecializedBase,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id),
        SerializersCodeGen::Attribute.new(name: :name, source: :name)
      ],
      method_attributes: [
        SerializersCodeGen::MethodAttribute.new(name: :greeting, body: :greeting),
        SerializersCodeGen::MethodAttribute.new(name: :static, body: -> { 42 })
      ],
      associations: []
    )
    MODES = %i[json hash]

    def self.sanity_record
      ParentClassSpecializedRecord.new(id: 1, name: "alice")
    end

    def self.expected_output(mode)
      case mode
      when :json then '{"id":1,"name":"alice","greeting":"Hi, alice!","static":42}'
      when :hash
        {"id" => 1, "name" => "alice", "greeting" => "Hi, alice!", "static" => 42}
      end
    end
  end
end
