# frozen_string_literal: true

# Canonical fixture for S17.2 (#91) — pins the new +scope+ axis added in
# +docs/code-generation.md § Callable hoisting+. Exercises every emit
# surface the widening touches:
#
# - one arity-2 Method Attribute (+legacy_label+) — proves +context+
#   still threads as +.call(record, context)+ unchanged.
# - one arity-3 Method Attribute (+viewer_label+) — proves +scope+
#   reaches the third positional arg as +.call(record, context, scope)+.
# - one +has_one :author+ with an arity-3 +if:+ Callable — proves the
#   Association-side Callable surface also gets +scope+.
# - one nested +ScopeThreadingCommentSerializer+ (via +has_many
#   :comments+) carrying its own arity-3 Method Attribute (+viewer_tag+)
#   — proves +scope+ identity is preserved through Composition into a
#   child Generated Class.
#
# Snapshot-only fixture: the +scope+ values in +sanity_record+ /
# +expected_output+ are observable in the rendered string so a future
# emit drift that drops +scope+ at any of those four surfaces fails
# byte-equality.
module Fixtures
  module ScopeThreading
    AUTHOR_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "ScopeThreadingAuthorSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id),
        SerializersCodeGen::Attribute.new(name: :name, source: :name)
      ],
      method_attributes: [],
      associations: []
    )

    COMMENT_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "ScopeThreadingCommentSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id),
        SerializersCodeGen::Attribute.new(name: :body, source: :body)
      ],
      method_attributes: [
        SerializersCodeGen::MethodAttribute.new(
          name: :viewer_tag,
          body: ->(record, _context, scope) { "#{scope}:#{record["body"]}" }
        )
      ],
      associations: []
    )

    CONFIG = SerializersCodeGen::Config.new
    DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "ScopeThreadingPostSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id)
      ],
      method_attributes: [
        SerializersCodeGen::MethodAttribute.new(
          name: :legacy_label,
          body: ->(record, context) { "#{context}:#{record["id"]}" }
        ),
        SerializersCodeGen::MethodAttribute.new(
          name: :viewer_label,
          body: ->(record, _context, scope) { "#{scope}:#{record["id"]}" }
        )
      ],
      associations: [
        SerializersCodeGen::Association.new(
          name: :author,
          kind: :has_one,
          descriptor: AUTHOR_DESCRIPTOR,
          if: ->(_record, _context, scope) { !scope.nil? }
        ),
        SerializersCodeGen::Association.new(
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

    def self.sanity_context
      "ctx"
    end

    def self.sanity_scope
      "viewer"
    end

    def self.expected_output(mode)
      case mode
      when :json
        '{"id":1,' \
          '"author":{"id":7,"name":"alice"},' \
          '"comments":[' \
          '{"id":11,"body":"first","viewer_tag":"viewer:first"},' \
          '{"id":12,"body":"second","viewer_tag":"viewer:second"}' \
          "]," \
          '"legacy_label":"ctx:1",' \
          '"viewer_label":"viewer:1"}'
      when :hash
        {
          "id" => 1,
          "author" => {"id" => 7, "name" => "alice"},
          "comments" => [
            {"id" => 11, "body" => "first", "viewer_tag" => "viewer:first"},
            {"id" => 12, "body" => "second", "viewer_tag" => "viewer:second"}
          ],
          "legacy_label" => "ctx:1",
          "viewer_label" => "viewer:1"
        }
      end
    end
  end
end
