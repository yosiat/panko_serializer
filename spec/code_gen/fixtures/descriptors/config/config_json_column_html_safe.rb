# frozen_string_literal: true

module Fixtures
  module Config
    # Config-isolation fixture pinning +Config#json_column_emit: :html_safe+ —
    # the opt-in mode that keeps today's +push_value(record._read_attribute(...))+
    # shape so consumers that embed scg output directly into HTML script
    # tags retain Oj +:rails+-mode HTML escaping. Same Descriptor as
    # {Fixtures::Config::ConfigJsonColumnWireFormat}; only the Config
    # field flips. The snapshot delta is the absence of +push_json+ /
    # +Oj.sc_parse+ in the body of +_write_one+ — every JSON-typed
    # Attribute keeps the canonical +push_key+ + +push_value+ pair.
    module ConfigJsonColumnHtmlSafe
      CONFIG = Panko::CodeGen::Config.new(json_column_emit: :html_safe)
      DESCRIPTOR = Panko::CodeGen::Descriptor.new(
        name: "ConfigJsonColumnHtmlSafeSerializer",
        models: [PlainPost],
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
