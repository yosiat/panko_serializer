# frozen_string_literal: true

require_relative "support/benchmark"

# --- FilterBuild — Filter.wrap construction overhead, isolated -----------
# Measures the per-call cost of building a `Filter` object from a
# caller-supplied `filters:` Hash, in isolation from emit. The dynamic
# case (a fresh Hash parsed from a query string per request) pays this
# cost on every `serialize_one` / `serialize_many` call; the existing
# `filter_only` / `filter_except` scenarios bundle this cost inside the
# emit IPS, so this scenario isolates it for direct inspection.
#
# Three Descriptor shapes span the representation-choice space (per
# `lib/serializers_code_gen/filters/indexed.rb` § INDEXED_BITS_THRESHOLD):
#
#   * `Flat5`  —  5 attrs (≤ 63) → Bits rep (Integer bit-mask, tagged
#                 Fixnum on 64-bit Ruby).
#   * `Flat70` — 70 attrs (>  63) → Array rep (Boolean Array).
#   * `Deep`   —  3-level nesting (Root + has_one Child + has_one GC,
#                 3 attrs/level) → exercises the child-Filter cache;
#                 the cache is lifetime-scoped to one `serialize_*`
#                 call, so a `has_many` iteration consults it once at
#                 hoist time and pays zero per-record after.
#
# Two filter-Hash flavors per Bits row:
#
#   * `frozen-hash`  — pre-allocated, frozen Hash reused per call.
#                      Measures pure `Filter.wrap` work.
#   * `fresh-hash`   — Hash literal allocated inside the block. Models
#                      the dynamic case (one Hash per request); the
#                      delta vs `frozen-hash` is the caller-side
#                      Hash-allocation cost, not anything `Filter.wrap`
#                      controls.
#
# Note: this scenario records construction-only IPS — there is no
# `panko` / `oj_serializers` / `plain` row because filter construction
# is internal to scg. The harness's `benchmark` primitive is invoked
# directly (no `benchmark_scenario` wrapper) since there is no
# per-`size` records list to pass through.

def make_filter_build_attrs(names)
  names.map { |n| SerializersCodeGen::Attribute.new(name: n, source: n) }
end

FILTER_BUILD_FLAT5_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "FilterBuildFlat5",
  models: nil,
  attributes: make_filter_build_attrs(%i[a b c d e]),
  method_attributes: [],
  associations: []
)

FILTER_BUILD_FLAT70_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "FilterBuildFlat70",
  models: nil,
  attributes: make_filter_build_attrs((1..70).map { |i| :"f#{i}" }),
  method_attributes: [],
  associations: []
)

FILTER_BUILD_GC_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "FilterBuildGrandchild",
  models: nil,
  attributes: make_filter_build_attrs(%i[x y z]),
  method_attributes: [],
  associations: []
)
FILTER_BUILD_CHILD_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "FilterBuildChild",
  models: nil,
  attributes: make_filter_build_attrs(%i[p q r]),
  method_attributes: [],
  associations: [
    SerializersCodeGen::Association.new(name: :gc, kind: :has_one, source: :gc, descriptor: FILTER_BUILD_GC_DESCRIPTOR)
  ]
)
FILTER_BUILD_DEEP_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "FilterBuildDeep",
  models: nil,
  attributes: make_filter_build_attrs(%i[a b c]),
  method_attributes: [],
  associations: [
    SerializersCodeGen::Association.new(name: :child, kind: :has_one, source: :child, descriptor: FILTER_BUILD_CHILD_DESCRIPTOR)
  ]
)

FILTER_BUILD_FLAT5_FIELD_INDEX = SerializersCodeGen.compile(FILTER_BUILD_FLAT5_DESCRIPTOR, output: :json).const_get(:FIELD_INDEX)
FILTER_BUILD_FLAT70_FIELD_INDEX = SerializersCodeGen.compile(FILTER_BUILD_FLAT70_DESCRIPTOR, output: :json).const_get(:FIELD_INDEX)
FILTER_BUILD_DEEP_FIELD_INDEX = SerializersCodeGen.compile(FILTER_BUILD_DEEP_DESCRIPTOR, output: :json).const_get(:FIELD_INDEX)
FILTER_BUILD_CHILD_FIELD_INDEX = SerializersCodeGen.compile(FILTER_BUILD_CHILD_DESCRIPTOR, output: :json).const_get(:FIELD_INDEX)
SerializersCodeGen.compile(FILTER_BUILD_GC_DESCRIPTOR, output: :json) # ensure compiled

# Frozen filter Hashes — measures pure Filter.wrap work with no
# caller-side Hash allocation.
FILTER_BUILD_EMPTY_FROZEN = {}.freeze
FILTER_BUILD_FLAT5_ONLY_FROZEN = {only: %i[a b].freeze}.freeze
FILTER_BUILD_FLAT5_EXCEPT_FROZEN = {except: %i[b].freeze}.freeze
FILTER_BUILD_FLAT70_SPARSE_FROZEN = {only: %i[f1 f2 f3].freeze}.freeze
FILTER_BUILD_FLAT70_DENSE_FROZEN = {only: (1..60).map { |i| :"f#{i}" }.freeze}.freeze
FILTER_BUILD_DEEP_FROZEN = {
  only: %i[a child].freeze,
  child: {only: %i[p gc].freeze, gc: {only: %i[x].freeze}.freeze}.freeze
}.freeze

# Pre-built parent with a warm child cache for the cached-lookup row.
# Built once at file load; every benchmark iteration hits the warm
# cache, isolating cache-lookup cost from Indexed.build cost.
FILTER_BUILD_PARENT_WARM = SerializersCodeGen::Filter.wrap(FILTER_BUILD_DEEP_FROZEN, FILTER_BUILD_DEEP_FIELD_INDEX)
FILTER_BUILD_PARENT_WARM.child(:child, FILTER_BUILD_CHILD_FIELD_INDEX)

# --- Rows -----------------------------------------------------------------

# NONE singleton — `filters: nil` and `filters: {}` both collapse here.
benchmark "FilterBuild/NONE/nil" do
  SerializersCodeGen::Filter.wrap(nil, FILTER_BUILD_FLAT5_FIELD_INDEX)
end

benchmark "FilterBuild/NONE/empty-hash" do
  SerializersCodeGen::Filter.wrap(FILTER_BUILD_EMPTY_FROZEN, FILTER_BUILD_FLAT5_FIELD_INDEX)
end

# Bits rep (≤ 63 fields) — flat 5-attr Descriptor.
benchmark "FilterBuild/Bits/5fields/only-2of5/frozen-hash" do
  SerializersCodeGen::Filter.wrap(FILTER_BUILD_FLAT5_ONLY_FROZEN, FILTER_BUILD_FLAT5_FIELD_INDEX)
end

benchmark "FilterBuild/Bits/5fields/only-2of5/fresh-hash" do
  SerializersCodeGen::Filter.wrap({only: [:a, :b]}, FILTER_BUILD_FLAT5_FIELD_INDEX)
end

benchmark "FilterBuild/Bits/5fields/except-1of5/frozen-hash" do
  SerializersCodeGen::Filter.wrap(FILTER_BUILD_FLAT5_EXCEPT_FROZEN, FILTER_BUILD_FLAT5_FIELD_INDEX)
end

# Array rep (> 63 fields) — flat 70-attr Descriptor. Sparse vs dense
# `:only` lists exercise the same per-Field walk in `Indexed.build`.
benchmark "FilterBuild/Array/70fields/only-3of70/frozen-hash" do
  SerializersCodeGen::Filter.wrap(FILTER_BUILD_FLAT70_SPARSE_FROZEN, FILTER_BUILD_FLAT70_FIELD_INDEX)
end

benchmark "FilterBuild/Array/70fields/only-60of70/frozen-hash" do
  SerializersCodeGen::Filter.wrap(FILTER_BUILD_FLAT70_DENSE_FROZEN, FILTER_BUILD_FLAT70_FIELD_INDEX)
end

# Deep nested — child Filters are built lazily on the first `.child(:src)`.
benchmark "FilterBuild/Deep/3level/wrap-only/frozen-hash" do
  SerializersCodeGen::Filter.wrap(FILTER_BUILD_DEEP_FROZEN, FILTER_BUILD_DEEP_FIELD_INDEX)
end

benchmark "FilterBuild/Deep/3level/wrap+1-child-cold/frozen-hash" do
  parent = SerializersCodeGen::Filter.wrap(FILTER_BUILD_DEEP_FROZEN, FILTER_BUILD_DEEP_FIELD_INDEX)
  parent.child(:child, FILTER_BUILD_CHILD_FIELD_INDEX)
end

benchmark "FilterBuild/Deep/3level/cached-child" do
  FILTER_BUILD_PARENT_WARM.child(:child, FILTER_BUILD_CHILD_FIELD_INDEX)
end
