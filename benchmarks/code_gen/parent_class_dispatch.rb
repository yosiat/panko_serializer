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
# n/a — panko / oj_serializers / plain rows omitted; this scenario
# compares scg variants against each other only. End-to-end perf vs
# Panko's C ext is the Panko-side slice 3.3 deliverable, not S18's
# (per `docs/merging-into-panko.md § Phase 3`).

class BenchParent
  def body_length
    @object.body.length
  end
end

PARENT_CLASS_DISPATCH_CALLABLE_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "ParentClassDispatchCallablePostBenchSerializer",
  models: [Bench::Post],
  attributes: [
    SerializersCodeGen::Attribute.new(name: :id, source: :id),
    SerializersCodeGen::Attribute.new(name: :title, source: :title)
  ],
  method_attributes: [
    SerializersCodeGen::MethodAttribute.new(
      name: :body_length,
      body: ->(record, _context) { record.body.length }
    )
  ],
  associations: []
)

PARENT_CLASS_DISPATCH_SYMBOL_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "ParentClassDispatchSymbolPostBenchSerializer",
  models: [Bench::Post],
  attributes: PARENT_CLASS_DISPATCH_CALLABLE_DESCRIPTOR.attributes,
  method_attributes: [
    SerializersCodeGen::MethodAttribute.new(name: :body_length, body: :body_length)
  ],
  associations: [],
  parent_class: BenchParent
)

SCG_JSON_PARENT_CLASS_CALLABLE = SerializersCodeGen.compile(PARENT_CLASS_DISPATCH_CALLABLE_DESCRIPTOR, output: :json).new(descriptor: PARENT_CLASS_DISPATCH_CALLABLE_DESCRIPTOR)
SCG_HASH_PARENT_CLASS_CALLABLE = SerializersCodeGen.compile(PARENT_CLASS_DISPATCH_CALLABLE_DESCRIPTOR, output: :hash).new(descriptor: PARENT_CLASS_DISPATCH_CALLABLE_DESCRIPTOR)
SCG_JSON_PARENT_CLASS_SYMBOL = SerializersCodeGen.compile(PARENT_CLASS_DISPATCH_SYMBOL_DESCRIPTOR, output: :json).new(descriptor: PARENT_CLASS_DISPATCH_SYMBOL_DESCRIPTOR)
SCG_HASH_PARENT_CLASS_SYMBOL = SerializersCodeGen.compile(PARENT_CLASS_DISPATCH_SYMBOL_DESCRIPTOR, output: :hash).new(descriptor: PARENT_CLASS_DISPATCH_SYMBOL_DESCRIPTOR)

# --- Target registry entries ----------------------------------------------
# n/a — panko / oj_serializers / plain rows omitted; this scenario compares
# scg variants against each other only.

Targets::SCG_JSON[:parent_class_dispatch_callable_body] = ->(records) { SCG_JSON_PARENT_CLASS_CALLABLE.serialize_many(records) }
Targets::SCG_HASH[:parent_class_dispatch_callable_body] = ->(records) { SCG_HASH_PARENT_CLASS_CALLABLE.serialize_many(records) }
Targets::SCG_JSON[:parent_class_dispatch_symbol_body] = ->(records) { SCG_JSON_PARENT_CLASS_SYMBOL.serialize_many(records) }
Targets::SCG_HASH[:parent_class_dispatch_symbol_body] = ->(records) { SCG_HASH_PARENT_CLASS_SYMBOL.serialize_many(records) }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "ParentClassDispatch", type: :posts do |records|
  {
    "serializers_code_gen/json[callable_body]" => -> { Targets::SCG_JSON[:parent_class_dispatch_callable_body].call(records) },
    "serializers_code_gen/hash[callable_body]" => -> { Targets::SCG_HASH[:parent_class_dispatch_callable_body].call(records) },
    "serializers_code_gen/json[symbol_body]" => -> { Targets::SCG_JSON[:parent_class_dispatch_symbol_body].call(records) },
    "serializers_code_gen/hash[symbol_body]" => -> { Targets::SCG_HASH[:parent_class_dispatch_symbol_body].call(records) }
  }
end
