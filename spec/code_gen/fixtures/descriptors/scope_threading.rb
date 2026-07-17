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
    AUTHOR_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "ScopeThreadingAuthorSerializer",
      model: nil,
      parent_class: Fixtures::BaseSerializer,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :name, source: :name)
      ],
      method_attributes: [],
      associations: []
    )

    COMMENT_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "ScopeThreadingCommentSerializer",
      model: nil,
      parent_class: Fixtures::BaseSerializer,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :body, source: :body)
      ],
      method_attributes: [
        Panko::CodeGen::MethodAttribute.new(
          name: :viewer_tag,
          body: ->(record, _context, scope) { "#{scope}:#{record["body"]}" }
        )
      ],
      associations: []
    )

    CONFIG = Panko::CodeGen::Config.new
    DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "ScopeThreadingPostSerializer",
      model: nil,
      parent_class: Fixtures::BaseSerializer,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id)
      ],
      method_attributes: [
        Panko::CodeGen::MethodAttribute.new(
          name: :legacy_label,
          body: ->(record, context) { "#{context}:#{record["id"]}" }
        ),
        Panko::CodeGen::MethodAttribute.new(
          name: :viewer_label,
          body: ->(record, _context, scope) { "#{scope}:#{record["id"]}" }
        )
      ],
      associations: [
        Panko::CodeGen::Association.new(
          name: :author,
          kind: :has_one,
          descriptor: AUTHOR_DESCRIPTOR,
          if: ->(_record, _context, scope) { !scope.nil? }
        ),
        Panko::CodeGen::Association.new(
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
