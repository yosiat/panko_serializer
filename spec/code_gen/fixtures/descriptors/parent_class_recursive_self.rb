# frozen_string_literal: true

# Canonical S18 fixture for parent_class + self-recursion shape per
# the parent S18 PRD (#95). +CommentSerializer has_many :replies,
# serializer: CommentSerializer+ shape — the Descriptor is constructed
# with an empty +associations:+ array, then the self-referencing
# +Association+ is appended after the Descriptor exists (mirror of
# +spec/fixtures/descriptors/recursive_self.rb+ from S8 — Ruby +Data+
# types are immutable but the Field-kind arrays are not frozen).
#
# Pins the per-instance ivar isolation BYTE SHAPE: every per-call
# entry into +_write_one+ / +_to_hash+ writes its own +@object+ /
# +@context+ / +@scope+ ivars at the top of the dispatcher — visible
# in the snapshot as three +@<ivar> = ...+ lines preceding the
# +is_a?(Hash)+ branch. Combined with the S8 +@replies_serializer =
# self+ shortcut, the snapshot proves a self-recursive Descriptor
# under +parent_class:+ keeps the K1 dispatch shape: one Generated
# Class instance, per-call ivar writes, native Ruby method dispatch
# on the parent class.
#
# The Symbol-body Method Attribute +:viewer_tag+ reads +@scope+ — the
# same value is threaded by every recursive call (+serialize_one+ sets
# scope once; the inner +_write_one+ calls forward it unchanged), so
# the byte-output is stable at every depth. The runtime-contract test
# for "each nested level sees its own +@object+" lives in
# +spec/features/concerns/parent_class_dispatch_spec.rb+ item (8) —
# the fixture's job is to pin the snapshot bytes, not the runtime
# contract.
class ParentClassRecursiveBase
  # Symbol-body Method Attribute +:viewer_tag+ dispatches here on
  # +self+ at every recursion depth. Reads +@scope+ — set by the
  # per-record ivar writes prepended to the Generic dispatcher in
  # +Generators::RecordAccess::Generic.emit_json_dispatch+ /
  # +emit_hash_dispatch+; the value is the same at every depth
  # because every recursive +_write_one+ call forwards +scope+
  # unchanged from the outer +serialize_one+ kwarg.
  #
  # @return [String]
  def viewer_tag
    "viewer=#{@scope}"
  end
end

module Fixtures
  module ParentClassRecursiveSelf
    CONFIG = SerializersCodeGen::Config.new
    DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "ParentClassRecursiveSelfCommentSerializer",
      models: nil,
      parent_class: ParentClassRecursiveBase,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id),
        SerializersCodeGen::Attribute.new(name: :body, source: :body)
      ],
      method_attributes: [
        SerializersCodeGen::MethodAttribute.new(name: :viewer_tag, body: :viewer_tag)
      ],
      associations: []
    )
    DESCRIPTOR.associations << SerializersCodeGen::Association.new(
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
