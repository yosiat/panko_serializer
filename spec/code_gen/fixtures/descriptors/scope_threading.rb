# frozen_string_literal: true

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
