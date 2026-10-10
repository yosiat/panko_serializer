# frozen_string_literal: true

module Fixtures
  module Config
    # +:html_safe+ keeps +push_value+ for JSON columns so Oj's :rails mode still
    # HTML-escapes output that callers embed in script tags.
    module ConfigJsonColumnHtmlSafe
      CONFIG = Panko::CodeGen::Config.new(json_column_emit: :html_safe)
      DESCRIPTOR = Panko::CodeGen::Descriptor.new(
        name: "ConfigJsonColumnHtmlSafeSerializer",
        model: PlainPost,
        parent_class: Fixtures::BaseSerializer,
        attributes: [
          Panko::CodeGen::Attribute.new(name: :id, source: :id),
          Panko::CodeGen::Attribute.new(name: :metadata, source: :metadata)
        ],
        method_attributes: [],
        associations: []
      )
      MODES = %i[json]

      def self.sanity_record
        PlainPost.new(id: 1, metadata: {"a" => 1, "b" => "x"})
      end

      def self.expected_output(mode)
        case mode
        when :json then '{"id":1,"metadata":{"a":1,"b":"x"}}'
        end
      end
    end
  end
end
