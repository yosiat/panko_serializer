# frozen_string_literal: true

require_relative "support/benchmark"

# Cost of building Filters (wrap and child) alone, without emit.
# The `fresh-hash` row allocates the filter Hash per call, like a filter parsed
# from each request. Calls `benchmark` directly: there is no records list to
# pass per size.

def make_filter_build_attrs(names)
  names.map { |n| Panko::CodeGen::Attribute.new(name: n, source: n) }
end

FILTER_BUILD_FLAT5_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "FilterBuildFlat5",
  model: nil,
  parent_class: Bench::BaseSerializer,
  attributes: make_filter_build_attrs(%i[a b c d e]),
  method_attributes: [],
  associations: []
)

FILTER_BUILD_FLAT70_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "FilterBuildFlat70",
  model: nil,
  parent_class: Bench::BaseSerializer,
  attributes: make_filter_build_attrs((1..70).map { |i| :"f#{i}" }),
  method_attributes: [],
  associations: []
)

FILTER_BUILD_GC_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "FilterBuildGrandchild",
  model: nil,
  parent_class: Bench::BaseSerializer,
  attributes: make_filter_build_attrs(%i[x y z]),
  method_attributes: [],
  associations: []
)
FILTER_BUILD_CHILD_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "FilterBuildChild",
  model: nil,
  parent_class: Bench::BaseSerializer,
  attributes: make_filter_build_attrs(%i[p q r]),
  method_attributes: [],
  associations: [
    Panko::CodeGen::Association.new(name: :gc, kind: :has_one, source: :gc, descriptor: FILTER_BUILD_GC_DESCRIPTOR)
  ]
)
FILTER_BUILD_DEEP_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "FilterBuildDeep",
  model: nil,
  parent_class: Bench::BaseSerializer,
  attributes: make_filter_build_attrs(%i[a b c]),
  method_attributes: [],
  associations: [
    Panko::CodeGen::Association.new(name: :child, kind: :has_one, source: :child, descriptor: FILTER_BUILD_CHILD_DESCRIPTOR)
  ]
)

FILTER_BUILD_FLAT5_FIELD_INDEX = Panko::CodeGen.compile(FILTER_BUILD_FLAT5_DESCRIPTOR, output: :json).const_get(:FIELD_INDEX)
FILTER_BUILD_FLAT70_FIELD_INDEX = Panko::CodeGen.compile(FILTER_BUILD_FLAT70_DESCRIPTOR, output: :json).const_get(:FIELD_INDEX)
FILTER_BUILD_DEEP_FIELD_INDEX = Panko::CodeGen.compile(FILTER_BUILD_DEEP_DESCRIPTOR, output: :json).const_get(:FIELD_INDEX)
FILTER_BUILD_CHILD_FIELD_INDEX = Panko::CodeGen.compile(FILTER_BUILD_CHILD_DESCRIPTOR, output: :json).const_get(:FIELD_INDEX)
Panko::CodeGen.compile(FILTER_BUILD_GC_DESCRIPTOR, output: :json)

# Built once at load, so the rows measure Filter.wrap with no caller-side Hash allocation.
FILTER_BUILD_EMPTY_FROZEN = {}.freeze
FILTER_BUILD_FLAT5_ONLY_FROZEN = {only: %i[a b].freeze}.freeze
FILTER_BUILD_FLAT5_EXCEPT_FROZEN = {except: %i[b].freeze}.freeze
FILTER_BUILD_FLAT70_SPARSE_FROZEN = {only: %i[f1 f2 f3].freeze}.freeze
FILTER_BUILD_FLAT70_DENSE_FROZEN = {only: (1..60).map { |i| :"f#{i}" }.freeze}.freeze
FILTER_BUILD_DEEP_FROZEN = {
  only: %i[a child].freeze,
  child: {only: %i[p gc].freeze, gc: {only: %i[x].freeze}.freeze}.freeze
}.freeze

# Warmed once at load, so the cached-child row measures only the cache lookup.
FILTER_BUILD_PARENT_WARM = Panko::CodeGen::Filter.wrap(FILTER_BUILD_DEEP_FROZEN, FILTER_BUILD_DEEP_FIELD_INDEX)
FILTER_BUILD_PARENT_WARM.child(:child, FILTER_BUILD_CHILD_FIELD_INDEX)

benchmark "FilterBuild/None/nil" do
  Panko::CodeGen::Filter.wrap(nil, FILTER_BUILD_FLAT5_FIELD_INDEX)
end

benchmark "FilterBuild/None/empty-hash" do
  Panko::CodeGen::Filter.wrap(FILTER_BUILD_EMPTY_FROZEN, FILTER_BUILD_FLAT5_FIELD_INDEX)
end

benchmark "FilterBuild/Indexed/5fields/only-2of5/frozen-hash" do
  Panko::CodeGen::Filter.wrap(FILTER_BUILD_FLAT5_ONLY_FROZEN, FILTER_BUILD_FLAT5_FIELD_INDEX)
end

benchmark "FilterBuild/Indexed/5fields/only-2of5/fresh-hash" do
  Panko::CodeGen::Filter.wrap({only: [:a, :b]}, FILTER_BUILD_FLAT5_FIELD_INDEX)
end

benchmark "FilterBuild/Indexed/5fields/except-1of5/frozen-hash" do
  Panko::CodeGen::Filter.wrap(FILTER_BUILD_FLAT5_EXCEPT_FROZEN, FILTER_BUILD_FLAT5_FIELD_INDEX)
end

benchmark "FilterBuild/Indexed/70fields/only-3of70/frozen-hash" do
  Panko::CodeGen::Filter.wrap(FILTER_BUILD_FLAT70_SPARSE_FROZEN, FILTER_BUILD_FLAT70_FIELD_INDEX)
end

benchmark "FilterBuild/Indexed/70fields/only-60of70/frozen-hash" do
  Panko::CodeGen::Filter.wrap(FILTER_BUILD_FLAT70_DENSE_FROZEN, FILTER_BUILD_FLAT70_FIELD_INDEX)
end

# Child Filters are built on the first `child` call, not by `wrap`.
benchmark "FilterBuild/Deep/3level/wrap-only/frozen-hash" do
  Panko::CodeGen::Filter.wrap(FILTER_BUILD_DEEP_FROZEN, FILTER_BUILD_DEEP_FIELD_INDEX)
end

benchmark "FilterBuild/Deep/3level/wrap+1-child-cold/frozen-hash" do
  parent = Panko::CodeGen::Filter.wrap(FILTER_BUILD_DEEP_FROZEN, FILTER_BUILD_DEEP_FIELD_INDEX)
  parent.child(:child, FILTER_BUILD_CHILD_FIELD_INDEX)
end

benchmark "FilterBuild/Deep/3level/cached-child" do
  FILTER_BUILD_PARENT_WARM.child(:child, FILTER_BUILD_CHILD_FIELD_INDEX)
end
