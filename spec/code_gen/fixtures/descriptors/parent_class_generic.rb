# frozen_string_literal: true

# Canonical S18 fixture for the Generic-path parent_class shape per
# the parent S18 PRD (#95). Mirrors +parent_class_specialized+'s
# descriptor shape but with +models: nil+, so the +_write_one+ /
# +_to_hash+ dispatchers + per-shape +_write_one_hash+ /
# +_write_one_object+ + +_to_hash_hash+ / +_to_hash_object+ helpers
# from +Generators::RecordAccess::Generic+ pin the parent_class
# ivar-write site: prepended to the *dispatcher* only — the helpers
# stay un-prepended because they inherit +@object+ / +@context+ /
# +@scope+ from the dispatcher that called them.
#
# The +sanity_record+ is a Hash so the Hash branch of the dispatcher
# fires; the Object branch is exercised by the feature-spec coverage
# (Struct-record cases under
# +spec/features/concerns/parent_class_dispatch_spec.rb+).
class ParentClassGenericBase
  # The Symbol-body Method Attribute +:greeting+ dispatches here via
  # direct method dispatch on +self+. Reads +@object+ — set by the
  # per-record ivar writes prepended to the Generic dispatcher in
  # +Generators::RecordAccess::Generic.emit_json_dispatch+ /
  # +emit_hash_dispatch+. The Hash-branch helper +_write_one_hash+
  # inherits the ivar from the dispatcher; the method here reads it
  # via +@object[...]+ since +sanity_record+ is a Hash.
  #
  # @return [String]
  def greeting
    "Hi, #{@object["name"]}!"
  end
end

module Fixtures
  module ParentClassGeneric
    CONFIG = SerializersCodeGen::Config.new
    DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "ParentClassGenericSerializer",
      models: nil,
      parent_class: ParentClassGenericBase,
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
      {"id" => 1, "name" => "alice"}
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
