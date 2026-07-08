# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- ParentClassDispatch — scg-only ---------------------------------------
# Two Descriptors with the same field set (`id` + `title` Attributes +
# `body_length` MethodAttribute) — one with a Callable-body
# MethodAttribute (today's contract, `parent_class: nil`), one with a
# Symbol-body MethodAttribute under `parent_class: BenchParent` (the S18
# direct-dispatch shape). Both go through the Specialized path via
# `models: [Bench::Post]`, so the only delta under measurement is the
# field-emitter Symbol-vs-Callable branch + per-record ivar writes.
#
# Encodes the load-bearing perf claim from PRD #95 — that Symbol-body
# dispatch (plus the three `@object` / `@context` / `@scope` ivar writes
# at the top of `_write_one` / `_to_hash`) is at-or-below Callable-body
# cost. A future emit-shape regression that adds dispatcher overhead
# (e.g. inadvertently reintroducing a J/A-shape wrapper) would trip a
# measurable IPS drop on the symbol_body rows rather than slipping in
# unnoticed.
#
# Carries a `panko/*` row: a Panko serializer's method attribute is an
# instance method (the symbol-body shape), so panko/json is the end-to-end
# cost of the same {id, title, body_length} emit through Panko's public
# API — measured next to the two raw-engine dispatch variants.

class BenchParent
  def body_length
    @object.body.length
  end
end

PARENT_CLASS_DISPATCH_CALLABLE_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "ParentClassDispatchCallablePostBenchSerializer",
  models: [Bench::Post],
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :title, source: :title)
  ],
  method_attributes: [
    Panko::CodeGen::MethodAttribute.new(
      name: :body_length,
      body: ->(record, _context) { record.body.length }
    )
  ],
  associations: []
)

PARENT_CLASS_DISPATCH_SYMBOL_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "ParentClassDispatchSymbolPostBenchSerializer",
  models: [Bench::Post],
  attributes: PARENT_CLASS_DISPATCH_CALLABLE_DESCRIPTOR.attributes,
  method_attributes: [
    Panko::CodeGen::MethodAttribute.new(name: :body_length, body: :body_length)
  ],
  associations: [],
  parent_class: BenchParent
)

SCG_JSON_PARENT_CLASS_CALLABLE = Panko::CodeGen.compile(PARENT_CLASS_DISPATCH_CALLABLE_DESCRIPTOR, output: :json).new(descriptor: PARENT_CLASS_DISPATCH_CALLABLE_DESCRIPTOR)
SCG_HASH_PARENT_CLASS_CALLABLE = Panko::CodeGen.compile(PARENT_CLASS_DISPATCH_CALLABLE_DESCRIPTOR, output: :hash).new(descriptor: PARENT_CLASS_DISPATCH_CALLABLE_DESCRIPTOR)
SCG_JSON_PARENT_CLASS_SYMBOL = Panko::CodeGen.compile(PARENT_CLASS_DISPATCH_SYMBOL_DESCRIPTOR, output: :json).new(descriptor: PARENT_CLASS_DISPATCH_SYMBOL_DESCRIPTOR)
SCG_HASH_PARENT_CLASS_SYMBOL = Panko::CodeGen.compile(PARENT_CLASS_DISPATCH_SYMBOL_DESCRIPTOR, output: :hash).new(descriptor: PARENT_CLASS_DISPATCH_SYMBOL_DESCRIPTOR)

class ParentClassDispatchPankoSerializer < Panko::Serializer
  attributes :id, :title, :body_length

  def body_length
    object.body.length
  end
end

# --- Target registry entries ----------------------------------------------

Targets::SCG_JSON[:parent_class_dispatch_callable_body] = ->(records) { SCG_JSON_PARENT_CLASS_CALLABLE.serialize_many(records) }
Targets::SCG_HASH[:parent_class_dispatch_callable_body] = ->(records) { SCG_HASH_PARENT_CLASS_CALLABLE.serialize_many(records) }
Targets::SCG_JSON[:parent_class_dispatch_symbol_body] = ->(records) { SCG_JSON_PARENT_CLASS_SYMBOL.serialize_many(records) }
Targets::SCG_HASH[:parent_class_dispatch_symbol_body] = ->(records) { SCG_HASH_PARENT_CLASS_SYMBOL.serialize_many(records) }
Targets::PANKO_JSON[:parent_class_dispatch] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: ParentClassDispatchPankoSerializer).to_json }
Targets::PANKO_OBJECT[:parent_class_dispatch] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: ParentClassDispatchPankoSerializer).to_a }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "ParentClassDispatch", type: :posts do |records|
  {
    "serializers_code_gen/json[callable_body]" => -> { Targets::SCG_JSON[:parent_class_dispatch_callable_body].call(records) },
    "serializers_code_gen/hash[callable_body]" => -> { Targets::SCG_HASH[:parent_class_dispatch_callable_body].call(records) },
    "serializers_code_gen/json[symbol_body]" => -> { Targets::SCG_JSON[:parent_class_dispatch_symbol_body].call(records) },
    "serializers_code_gen/hash[symbol_body]" => -> { Targets::SCG_HASH[:parent_class_dispatch_symbol_body].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:parent_class_dispatch].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:parent_class_dispatch].call(records) }
  }
end
