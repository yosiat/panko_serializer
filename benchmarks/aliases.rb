# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- Aliases-shape Descriptor / serializers -------------------------------
# Attributes whose output `name` differs from their `source` — the bench
# exercises the per-Field rename path. model: Bench::Post picks the
# specialized path on the scg row for an apples-to-apples comparison
# against panko/{json,object}.

ALIASES_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "AliasesPostBenchSerializer",
  model: Bench::Post,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :name, source: :title),
    Panko::CodeGen::Attribute.new(name: :content, source: :body),
    Panko::CodeGen::Attribute.new(name: :hits, source: :views)
  ],
  method_attributes: [],
  associations: []
)

SCG_JSON_ALIASES = Panko::CodeGen.compile(ALIASES_DESCRIPTOR, output: :json).new(descriptor: ALIASES_DESCRIPTOR)
SCG_HASH_ALIASES = Panko::CodeGen.compile(ALIASES_DESCRIPTOR, output: :hash).new(descriptor: ALIASES_DESCRIPTOR)

class AliasesPostPankoSerializer < Panko::Serializer
  attributes :id
  aliases title: :name, body: :content, views: :hits
end

class AliasesPostOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id
  attributes title: {as: :name}, body: {as: :content}, views: {as: :hits}
end

# --- Target registry entries ----------------------------------------------

Targets::SCG_JSON[:aliases] = ->(records) { SCG_JSON_ALIASES.serialize_many(records) }
Targets::SCG_HASH[:aliases] = ->(records) { SCG_HASH_ALIASES.serialize_many(records) }
Targets::PANKO_JSON[:aliases] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: AliasesPostPankoSerializer).to_json }
Targets::PANKO_OBJECT[:aliases] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: AliasesPostPankoSerializer).to_a }
Targets::OJ_JSON[:aliases] = ->(records) { AliasesPostOjSerializer.many(records).to_s }
Targets::PLAIN_JSON[:aliases] = ->(records) { records.map { |r| {id: r.id, name: r.title, content: r.body, hits: r.views} }.to_json }
Targets::PLAIN_HASH[:aliases] = ->(records) { records.map { |r| {id: r.id, name: r.title, content: r.body, hits: r.views} } }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "Aliases", type: :posts do |records|
  {
    "serializers_code_gen/json" => -> { Targets::SCG_JSON[:aliases].call(records) },
    "serializers_code_gen/hash" => -> { Targets::SCG_HASH[:aliases].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:aliases].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:aliases].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:aliases].call(records) },
    "plain/json" => -> { Targets::PLAIN_JSON[:aliases].call(records) },
    "plain/hash" => -> { Targets::PLAIN_HASH[:aliases].call(records) }
  }
end
