# frozen_string_literal: true

# Phase-2 filter-experiment harness — measures the 2x2 cell matrix
# `{Hash-wrapper, Set-index} x {single-path, dual-path}` against 5 fixtures
# x a record-count sweep, exercising the real compiled
# `SerializersCodeGen` Generated Class via per-cell `module_eval` overlays
# per `docs/filters.md § Experiment design`.
#
# Run (YJIT — the production target):
#   bundle exec ruby --yjit filter_experiments_bench.rb
#
# Tunables (env vars):
#   IPS_TIME=5     benchmark-ips measurement seconds (default 5)
#   IPS_WARMUP=3   benchmark-ips warmup seconds      (default 3)
#
# S13.2 acceptance: harness runs end-to-end with short `IPS_TIME` (e.g.
# IPS_TIME=1) and produces structurally-correct output for every cell x
# fixture x size. Canonical timed run with long `IPS_TIME` is S13.3 — this
# file is the harness only; the verdict-backfill pass lives there.
#
# Self-contained per `docs/research/` convention (mirrors
# `ar_access_bench.rb` / `game_serializer_bench.rb`): inline AR
# sqlite-in-memory schema + AR models + dataset seeding; does not reuse
# `benchmarks/support/` or `spec/support/`.

require "active_record"
require "sqlite3"
require "benchmark/ips"
require "memory_profiler"
require "oj"
require "date"

# Local scg, loaded from the repo's lib/. This script lives at
# `docs/research/`, so `../../lib` resolves to the gem's `lib/`.
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "serializers_code_gen"

RubyVM::YJIT.enable if defined?(RubyVM::YJIT)

# ---- Tunables --------------------------------------------------------------

IPS_TIME = Integer(ENV.fetch("IPS_TIME", "5"))
IPS_WARMUP = Integer(ENV.fetch("IPS_WARMUP", "3"))

# ---- AR setup --------------------------------------------------------------

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false

# Wide-flat shape: 30 string + 20 integer + 10 boolean + 5 decimal + 5 date
# = 70 columns split across the four AR primitive types — mirrors
# `WIDE_POST_ATTRIBUTE_NAMES` from `benchmarks/wide_attributes.rb` so the
# experiment stresses per-Field emit + dispatch on the same shape the
# canonical benchmarks measure.
WIDE_STRING_COUNT = 30
WIDE_INTEGER_COUNT = 20
WIDE_BOOLEAN_COUNT = 10
WIDE_DECIMAL_COUNT = 5
WIDE_DATE_COUNT = 5

WIDE_STRING_NAMES = (1..WIDE_STRING_COUNT).map { |i| "s_%02d" % i }.freeze
WIDE_INTEGER_NAMES = (1..WIDE_INTEGER_COUNT).map { |i| "i_%02d" % i }.freeze
WIDE_BOOLEAN_NAMES = (1..WIDE_BOOLEAN_COUNT).map { |i| "b_%02d" % i }.freeze
WIDE_DECIMAL_NAMES = (1..WIDE_DECIMAL_COUNT).map { |i| "d_%02d" % i }.freeze
WIDE_DATE_NAMES = (1..WIDE_DATE_COUNT).map { |i| "t_%02d" % i }.freeze
WIDE_ATTRIBUTE_NAMES = (
  WIDE_STRING_NAMES + WIDE_INTEGER_NAMES + WIDE_BOOLEAN_NAMES +
    WIDE_DECIMAL_NAMES + WIDE_DATE_NAMES
).freeze

ActiveRecord::Schema.define do
  create_table :flt_posts, force: true do |t|
    t.string :title
    t.string :body
    t.integer :views
    t.boolean :published
  end

  create_table :flt_authors, force: true do |t|
    t.references :flt_post
    t.string :name
    t.string :email
  end

  create_table :flt_comments, force: true do |t|
    t.references :flt_post
    t.string :body
  end

  create_table :flt_wide_posts, force: true do |t|
    WIDE_STRING_NAMES.each { |n| t.string n }
    WIDE_INTEGER_NAMES.each { |n| t.integer n }
    WIDE_BOOLEAN_NAMES.each { |n| t.boolean n }
    WIDE_DECIMAL_NAMES.each { |n| t.decimal n, precision: 12, scale: 2 }
    WIDE_DATE_NAMES.each { |n| t.date n }
  end
end

module FilterBench
  class Post < ActiveRecord::Base
    self.table_name = "flt_posts"
    has_one :author, class_name: "FilterBench::Author", foreign_key: :flt_post_id
    has_many :comments, class_name: "FilterBench::Comment", foreign_key: :flt_post_id

    # Reads from the already-eager-loaded `:comments` collection so the
    # `:first_comment` Association source on `GRAPH_DESCRIPTOR` doesn't
    # trigger an N+1 query inside the measured block.
    def first_comment
      comments.first
    end
  end

  class Author < ActiveRecord::Base
    self.table_name = "flt_authors"
    belongs_to :post, class_name: "FilterBench::Post", foreign_key: :flt_post_id, optional: true
  end

  class Comment < ActiveRecord::Base
    self.table_name = "flt_comments"
    belongs_to :post, class_name: "FilterBench::Post", foreign_key: :flt_post_id, optional: true
  end

  class WidePost < ActiveRecord::Base
    self.table_name = "flt_wide_posts"
  end
end

[FilterBench::Post, FilterBench::Author, FilterBench::Comment, FilterBench::WidePost]
  .each(&:define_attribute_methods)

# ---- Dataset seeding -------------------------------------------------------

# `MAX_SIZE` matches the largest size in the matrix; the bench slices to
# the requested size each iteration. 5 comments per post mirrors the
# graph.rb scenario in `benchmarks/`.
MAX_SIZE = 2300
COMMENTS_PER_POST = 5

post_attrs = Array.new(MAX_SIZE) do |i|
  {title: "Post ##{i}", body: "Body of post ##{i}", views: i, published: i.even?}
end
FilterBench::Post.insert_all(post_attrs)

post_ids = FilterBench::Post.pluck(:id)

author_attrs = post_ids.map.with_index do |post_id, i|
  {flt_post_id: post_id, name: "Author ##{i}", email: "author#{i}@example.com"}
end
FilterBench::Author.insert_all(author_attrs)

comment_attrs = post_ids.flat_map do |post_id|
  Array.new(COMMENTS_PER_POST) { |j| {flt_post_id: post_id, body: "Comment ##{j}"} }
end
FilterBench::Comment.insert_all(comment_attrs)

# Wide-post seeding — 70 columns x 2300 rows = 161 000 placeholders. Sqlite
# caps `SQLITE_MAX_VARIABLE_NUMBER` at 32 766 on modern builds; batch at
# 400 rows so each insert stays under that limit (400 x 70 = 28 000).
WIDE_POST_INSERT_BATCH = 400
base_date = Date.new(2025, 1, 1)
wide_attrs = Array.new(MAX_SIZE) do |i|
  row = {}
  WIDE_STRING_NAMES.each_with_index { |n, j| row[n] = "s#{j}_v#{i}" }
  WIDE_INTEGER_NAMES.each_with_index { |n, j| row[n] = i + j }
  WIDE_BOOLEAN_NAMES.each_with_index { |n, j| row[n] = (i + j).even? }
  WIDE_DECIMAL_NAMES.each_with_index { |n, j| row[n] = "%.2f" % ((i * 100 + j) / 100.0) }
  WIDE_DATE_NAMES.each_with_index { |n, j| row[n] = base_date + (i + j) }
  row
end
wide_attrs.each_slice(WIDE_POST_INSERT_BATCH) { |slice| FilterBench::WidePost.insert_all(slice) }

# Eager-load author + comments for the graph fixture so the measured loop
# doesn't pay an N+1 query cost. Frozen so accidental mutation surfaces as
# `FrozenError` rather than measurement drift.
WIDE_RECORDS = FilterBench::WidePost.all.to_a.freeze
GRAPH_RECORDS = FilterBench::Post.includes(:author, :comments).to_a.freeze

# ---- Filter classes --------------------------------------------------------
#
# Three implementations sharing the `drops?(name) / child(source) / none?`
# interface from `docs/filters.md § Threading through Composition`. The 2x2
# matrix multiplies `{HashWrapperFilter, SetIndexFilter}` x emit-strategy
# overlay (applied to the Generated Class body via `module_eval`).
# `NoneFilter` is the C-axis from `docs/filters.md § No-filter fast path` —
# the singleton used when the caller passes no filter; same singleton across
# both representations.
#
# Per `docs/filters.md § Internal representation — experiment-driven`:
# - `HashWrapperFilter` is Option A — zero upfront cost, O(n) per check.
# - `SetIndexFilter` is Option B — one walk + allocations upfront, O(1)
#   per check.

# Singleton "no filter in effect" Filter object — `drops?` always false,
# `child` always self, `none?` true. Frozen so identity is stable across
# the program lifetime; both representations recursively collapse to this
# singleton when a sub-Hash is missing or empty per
# `docs/filters.md § Public shape` ("Empty Hash `{}` at a level is
# equivalent to `nil` at that level — no filtering").
class NoneFilter
  def drops?(_name)
    false
  end

  def child(_source)
    self
  end

  def none?
    true
  end

  INSTANCE = new.freeze
end

# Filter representation A — wraps the caller's nested Hash directly. No
# copy, no upfront walk, no normalization. `drops?` does direct Hash
# lookups + `Array#include?` (O(n) per check); `child` allocates a new
# wrapper around the sub-Hash on each call (or returns `NoneFilter::INSTANCE`
# when the sub-Hash is empty / missing). The fair test of "lazy O(n)
# per check" per `#55` user story 31.
class HashWrapperFilter
  def initialize(hash)
    @hash = hash
    @only = hash[:only]
    @except = hash[:except]
  end

  def drops?(name)
    return !@only.include?(name) if @only
    return @except.include?(name) if @except
    false
  end

  def child(source)
    sub = @hash[source]
    return NoneFilter::INSTANCE if sub.nil? || sub.empty?
    HashWrapperFilter.new(sub)
  end

  def none?
    false
  end
end

# Filter representation B — at construction, walks the Hash once and
# builds per-level `Set`s keyed by node name + a Hash of child Filter
# objects keyed by Source. `drops?` is O(1) `Set#include?`; `child`
# returns the cached sub-Filter (or `NoneFilter::INSTANCE` when the
# sub-Hash was empty / missing at construction). The fair test of
# "amortized O(1) per check" per `#55` user story 32 — one upfront walk,
# many cheap lookups.
class SetIndexFilter
  def initialize(hash)
    only = hash[:only]
    except = hash[:except]
    @only_set = only && Set.new(only)
    @except_set = except && Set.new(except)
    @children = {}
    hash.each do |key, value|
      next if key == :only || key == :except
      next if value.nil? || value.empty?
      @children[key] = SetIndexFilter.new(value)
    end
  end

  def drops?(name)
    return !@only_set.include?(name) if @only_set
    return @except_set.include?(name) if @except_set
    false
  end

  def child(source)
    @children[source] || NoneFilter::INSTANCE
  end

  def none?
    false
  end
end

# Filter representation C — codegen-time field indexing. Each Field
# (Attribute / MethodAttribute / Association, in declared order on the
# Descriptor) gets a 0-based index assigned at overlay-emit time, baked
# into the +unless filters.drops?(<integer>)+ check site as an integer
# literal. The Filter object stores the drop set as either an Integer
# bit-mask (when the Descriptor's Field count fits in 63 bits — a
# tagged Fixnum on 64-bit, so bit ops avoid Bignum boxing) or a Boolean
# Array (when the Field count exceeds 63). +drops?+ is then a single
# +Integer#[]+ shift+and (bits) or +Array#[]+ load (array) — no symbol
# hashing, no Set probe. Per the +#59+ HITL extension to the
# pre-registered cell matrix; rationale + decision-rule re-application
# are recorded in the results doc § 4 + § 8.

class IndexedBitsFilter
  def initialize(drops_mask, children)
    @drops_mask = drops_mask
    @children = children
  end

  def drops?(index)
    @drops_mask[index] == 1
  end

  def child(source)
    @children[source] || NoneFilter::INSTANCE
  end

  def none?
    false
  end
end

class IndexedArrayFilter
  def initialize(drops_array, children)
    @drops = drops_array
    @children = children
  end

  def drops?(index)
    @drops[index]
  end

  def child(source)
    @children[source] || NoneFilter::INSTANCE
  end

  def none?
    false
  end
end

# Builds an indexed Filter for +descriptor+ from the caller's +hash+.
# Walks the Descriptor once at construction (like Set-index) to:
#   1. Resolve each Field name in the caller's +:only+ / +:except+ into
#      its declared-order integer position on the Descriptor.
#   2. Pick the dynamic representation: Integer bit-mask when the Field
#      count <= 63, Boolean Array otherwise. The threshold is the
#      tagged-Fixnum cap on 64-bit (Bignum boxing of a 64-bit literal
#      makes +Integer#[]+ stop being constant-time).
#   3. Recursively build child Filters for each sub-Hash whose key
#      matches an Association +source+ on the Descriptor — child
#      indices are computed against the child Descriptor's Field
#      ordering, so each level uses its own integer space.
#
# Unknown sub-Hash keys are silently dropped (matches HashWrapper /
# Set-index per +docs/filters.md § Unknown keys+). Empty / +nil+
# sub-Hashes collapse to +NoneFilter::INSTANCE+ via the lookup miss in
# +child+.
module IndexedFilter
  module_function

  BIT_THRESHOLD = 63
  # Cache of per-Descriptor frozen field-name lists, keyed by
  # +Descriptor#__id__+. The field list is fixed at compile time on a
  # Descriptor (Data.define is immutable); production codegen would bake
  # it into a per-class constant. This cache plays the equivalent role
  # in the bench so +IndexedFilter.build+'s per-call allocation profile
  # matches what production would ship.
  DESCRIPTOR_FIELDS_CACHE = {}
  # Frozen empty Hash returned from +build_children+ when the caller's
  # filter Hash has no Association sub-Hashes. Avoids a fresh empty Hash
  # allocation per +serialize_*+ call on shallow-only fixtures.
  EMPTY_CHILDREN = {}.freeze

  def build(descriptor, hash)
    fields = descriptor_fields(descriptor)
    n = fields.size
    only = hash[:only]
    except = hash[:except]
    only_set = only && (only.is_a?(Set) ? only : Set.new(only))
    except_set = except && (except.is_a?(Set) ? except : Set.new(except))

    if n <= BIT_THRESHOLD
      # Bit-mask path: accumulate into a single Integer, no intermediate
      # Array. +0+ allocations besides the Filter object + children.
      mask = 0
      i = 0
      while i < n
        name = fields[i]
        drop = if only_set
          !only_set.include?(name)
        elsif except_set
          except_set.include?(name)
        else
          false
        end
        mask |= (1 << i) if drop
        i += 1
      end
      IndexedBitsFilter.new(mask, build_children(descriptor, hash))
    else
      # Array path: pre-size with +nil+, fill in place. One Array
      # allocation regardless of drop count.
      arr = Array.new(n)
      i = 0
      while i < n
        name = fields[i]
        arr[i] = if only_set
          !only_set.include?(name)
        elsif except_set
          except_set.include?(name)
        else
          false
        end
        i += 1
      end
      IndexedArrayFilter.new(arr, build_children(descriptor, hash))
    end
  end

  # Field ordering: Attributes, then MethodAttributes, then Associations,
  # each in declared order on the Descriptor. Codegen and Filter
  # construction MUST agree on this ordering or the integer indices
  # baked at codegen time will probe the wrong drops bit.
  #
  # @return [Array<Symbol>] Field names in canonical declared order.
  def descriptor_fields(descriptor)
    DESCRIPTOR_FIELDS_CACHE[descriptor.__id__] ||=
      (descriptor.attributes + descriptor.method_attributes + descriptor.associations).map(&:name).freeze
  end

  def build_children(descriptor, hash)
    children = nil
    hash.each do |key, value|
      next if key == :only || key == :except
      next if value.nil? || value.empty?
      assoc = descriptor.associations.find { |a| a.source == key }
      next unless assoc
      children ||= {}
      children[key] = build(assoc.descriptor, value)
    end
    children || EMPTY_CHILDREN
  end
end

# The cells the bench exercises. Originally a 2x2 product of
# +{Hash-wrapper, Set-index} x {single-path, dual-path}+ per the
# pre-registered matrix in +docs/filters.md § Decision rule+. The
# +indexed_single_path+ cell was added during +#59+ review per HITL
# scope amendment to evaluate the integer-indexed bool-array /
# bit-vector approach (see results doc § 4 + § 8 for the amendment
# record). +indexed_dual_path+ is intentionally omitted: dual-path's
# dispatcher branch buys nothing measurable on either of the
# pre-registered representations, so the indexed experiment runs
# single-path only.
CELL_NAMES = %i[
  hash_wrapper_single_path
  hash_wrapper_dual_path
  set_index_single_path
  set_index_dual_path
  indexed_single_path
].freeze

# ---- Overlay emitter -------------------------------------------------------
#
# Emits filter-aware Ruby source for a per-cell `_write_one` (and the
# dual-path `_write_one_unfiltered` / `_write_one_filtered` pair when the
# strategy is `:dual_path`) on top of an already-compiled Generated Class.
# Mirrors the per-Field shape `Generators::RecordAccess::Specialized`
# emits — `record._read_attribute("name")` for column-backed Attributes,
# `record.<source>` for Associations + per-Kind dispatch — and additionally
# threads the Filter object through `filters.drops?(name)` checks and
# `filters.child(source)` for nested calls per
# `docs/filters.md § Threading through Composition`.
#
# The overlay is the cell-specific shape under measurement. Per `#55` user
# story 23 the overlay's source is the drafting board that S14 lifts into
# `lib/serializers_code_gen/filters/<winner>.rb` once the verdict is in.
module Overlay
  module_function

  # Prepended to every overlay source string before +module_eval+. Mirrors
  # the +# frozen_string_literal: true+ line that production codegen emits
  # at line 1 of every Generated Class body
  # (+lib/serializers_code_gen/generators/{json,hash}_mode.rb+) so the
  # bench measures the same per-call allocation profile production will
  # ship: +"name"+ literals interned at parse time instead of allocated
  # per call. Without the pragma, +record._read_attribute("name")+ and
  # +writer.push_value(..., "name")+ allocate two fresh Strings per
  # attribute per record (+~140 strings/record on the wide-flat fixture+),
  # which dominates the bench numbers and hides the real Filter-object
  # overhead the verdict cares about.
  FROZEN_PRAGMA = "# frozen_string_literal: true\n\n"

  def emit_for(descriptor:, cell_name:, output:)
    body = case [cell_name, output]
    when [:hash_wrapper_single_path, :json], [:set_index_single_path, :json]
      emit_single_path_json(descriptor)
    when [:hash_wrapper_dual_path, :json], [:set_index_dual_path, :json]
      emit_dual_path_json(descriptor)
    when [:hash_wrapper_single_path, :hash], [:set_index_single_path, :hash]
      emit_single_path_hash(descriptor)
    when [:hash_wrapper_dual_path, :hash], [:set_index_dual_path, :hash]
      emit_dual_path_hash(descriptor)
    when [:indexed_single_path, :json] then emit_indexed_single_path_json(descriptor)
    when [:indexed_single_path, :hash] then emit_indexed_single_path_hash(descriptor)
    end
    FROZEN_PRAGMA + body
  end

  # ---- JSON ----

  def emit_single_path_json(descriptor)
    [
      "def _write_one(record, writer, context, filters)\n",
      "  writer.push_object\n",
      json_filtered_body(descriptor, indent: 2),
      "  writer.pop\n",
      "end\n\n",
      json_serialize_many_bench
    ].join
  end

  def emit_dual_path_json(descriptor)
    [
      "def _write_one(record, writer, context, filters)\n",
      "  if filters.none?\n",
      "    _write_one_unfiltered(record, writer, context)\n",
      "  else\n",
      "    _write_one_filtered(record, writer, context, filters)\n",
      "  end\n",
      "end\n\n",
      "def _write_one_unfiltered(record, writer, context)\n",
      "  writer.push_object\n",
      json_unfiltered_body(descriptor, indent: 2),
      "  writer.pop\n",
      "end\n\n",
      "def _write_one_filtered(record, writer, context, filters)\n",
      "  writer.push_object\n",
      json_filtered_body(descriptor, indent: 2),
      "  writer.pop\n",
      "end\n\n",
      json_serialize_many_bench
    ].join
  end

  def json_serialize_many_bench
    "def _serialize_many_bench(records, filter)\n" \
      "  writer = Oj::StringWriter.new(mode: :rails)\n" \
      "  writer.push_array\n" \
      "  records.each { |r| _write_one(r, writer, nil, filter) }\n" \
      "  writer.pop\n" \
      "  writer.to_s.chomp\n" \
      "end\n"
  end

  def json_filtered_body(descriptor, indent:)
    pad = " " * indent
    body = +""
    descriptor.attributes.each do |a|
      body << pad << "unless filters.drops?(:#{a.name})\n"
      body << pad << "  writer.push_value(record._read_attribute(\"#{a.source}\"), \"#{a.name}\")\n"
      body << pad << "end\n"
    end
    descriptor.associations.each do |assoc|
      body << emit_assoc_json_filtered(assoc, indent: indent)
    end
    body
  end

  def json_unfiltered_body(descriptor, indent:)
    pad = " " * indent
    body = +""
    descriptor.attributes.each do |a|
      body << pad << "writer.push_value(record._read_attribute(\"#{a.source}\"), \"#{a.name}\")\n"
    end
    descriptor.associations.each do |assoc|
      body << emit_assoc_json_unfiltered(assoc, indent: indent)
    end
    body
  end

  def emit_assoc_json_filtered(assoc, indent:)
    pad = " " * indent
    case assoc.kind
    when :has_one
      pad + "unless filters.drops?(:#{assoc.name})\n" +
        pad + "  value = record.#{assoc.source}\n" +
        pad + "  if value.nil?\n" +
        pad + "    writer.push_value(nil, \"#{assoc.name}\")\n" +
        pad + "  else\n" +
        pad + "    writer.push_key(\"#{assoc.name}\")\n" +
        pad + "    @#{assoc.name}_serializer._write_one(value, writer, context, filters.child(:#{assoc.source}))\n" +
        pad + "  end\n" +
        pad + "end\n"
    when :has_many
      pad + "unless filters.drops?(:#{assoc.name})\n" +
        pad + "  child_filter = filters.child(:#{assoc.source})\n" +
        pad + "  writer.push_array(\"#{assoc.name}\")\n" +
        pad + "  record.#{assoc.source}.each do |element|\n" +
        pad + "    @#{assoc.name}_serializer._write_one(element, writer, context, child_filter)\n" +
        pad + "  end\n" +
        pad + "  writer.pop\n" +
        pad + "end\n"
    end
  end

  def emit_assoc_json_unfiltered(assoc, indent:)
    pad = " " * indent
    case assoc.kind
    when :has_one
      pad + "value = record.#{assoc.source}\n" +
        pad + "if value.nil?\n" +
        pad + "  writer.push_value(nil, \"#{assoc.name}\")\n" +
        pad + "else\n" +
        pad + "  writer.push_key(\"#{assoc.name}\")\n" +
        pad + "  @#{assoc.name}_serializer._write_one_unfiltered(value, writer, context)\n" +
        pad + "end\n"
    when :has_many
      pad + "writer.push_array(\"#{assoc.name}\")\n" +
        pad + "record.#{assoc.source}.each do |element|\n" +
        pad + "  @#{assoc.name}_serializer._write_one_unfiltered(element, writer, context)\n" +
        pad + "end\n" +
        pad + "writer.pop\n"
    end
  end

  # ---- Hash ----

  def emit_single_path_hash(descriptor)
    [
      "def _to_hash(record, context, filters)\n",
      "  result = {}\n",
      hash_filtered_body(descriptor, indent: 2),
      "  result\n",
      "end\n\n",
      hash_serialize_many_bench
    ].join
  end

  def emit_dual_path_hash(descriptor)
    [
      "def _to_hash(record, context, filters)\n",
      "  if filters.none?\n",
      "    _to_hash_unfiltered(record, context)\n",
      "  else\n",
      "    _to_hash_filtered(record, context, filters)\n",
      "  end\n",
      "end\n\n",
      "def _to_hash_unfiltered(record, context)\n",
      "  result = {}\n",
      hash_unfiltered_body(descriptor, indent: 2),
      "  result\n",
      "end\n\n",
      "def _to_hash_filtered(record, context, filters)\n",
      "  result = {}\n",
      hash_filtered_body(descriptor, indent: 2),
      "  result\n",
      "end\n\n",
      hash_serialize_many_bench
    ].join
  end

  def hash_serialize_many_bench
    "def _serialize_many_bench(records, filter)\n" \
      "  records.map { |r| _to_hash(r, nil, filter) }\n" \
      "end\n"
  end

  def hash_filtered_body(descriptor, indent:)
    pad = " " * indent
    body = +""
    descriptor.attributes.each do |a|
      body << pad << "unless filters.drops?(:#{a.name})\n"
      body << pad << "  result[\"#{a.name}\"] = record._read_attribute(\"#{a.source}\")\n"
      body << pad << "end\n"
    end
    descriptor.associations.each do |assoc|
      body << emit_assoc_hash_filtered(assoc, indent: indent)
    end
    body
  end

  def hash_unfiltered_body(descriptor, indent:)
    pad = " " * indent
    body = +""
    descriptor.attributes.each do |a|
      body << pad << "result[\"#{a.name}\"] = record._read_attribute(\"#{a.source}\")\n"
    end
    descriptor.associations.each do |assoc|
      body << emit_assoc_hash_unfiltered(assoc, indent: indent)
    end
    body
  end

  def emit_assoc_hash_filtered(assoc, indent:)
    pad = " " * indent
    case assoc.kind
    when :has_one
      pad + "unless filters.drops?(:#{assoc.name})\n" +
        pad + "  value = record.#{assoc.source}\n" +
        pad + "  result[\"#{assoc.name}\"] = if value.nil?\n" +
        pad + "    nil\n" +
        pad + "  else\n" +
        pad + "    @#{assoc.name}_serializer._to_hash(value, context, filters.child(:#{assoc.source}))\n" +
        pad + "  end\n" +
        pad + "end\n"
    when :has_many
      pad + "unless filters.drops?(:#{assoc.name})\n" +
        pad + "  child_filter = filters.child(:#{assoc.source})\n" +
        pad + "  result[\"#{assoc.name}\"] = record.#{assoc.source}.map { |element| " \
                "@#{assoc.name}_serializer._to_hash(element, context, child_filter) }\n" +
        pad + "end\n"
    end
  end

  def emit_assoc_hash_unfiltered(assoc, indent:)
    pad = " " * indent
    case assoc.kind
    when :has_one
      pad + "value = record.#{assoc.source}\n" +
        pad + "result[\"#{assoc.name}\"] = if value.nil?\n" +
        pad + "  nil\n" +
        pad + "else\n" +
        pad + "  @#{assoc.name}_serializer._to_hash_unfiltered(value, context)\n" +
        pad + "end\n"
    when :has_many
      pad + "result[\"#{assoc.name}\"] = record.#{assoc.source}.map { |element| " \
              "@#{assoc.name}_serializer._to_hash_unfiltered(element, context) }\n"
    end
  end

  # ---- Indexed (single-path only) ----
  #
  # Field-index ordering MUST match +IndexedFilter.descriptor_fields+:
  # +attributes + method_attributes + associations+, each in declared
  # order. The integer literal at every check site is resolved at
  # codegen time from this ordering; the Filter object built per
  # +serialize_*+ call uses the same ordering to set its drop bits.
  # Drift between codegen and Filter construction would silently probe
  # the wrong bit; pre-flight byte-equivalence catches it as a divergent
  # output rather than a wrong-but-still-valid one.

  def emit_indexed_single_path_json(descriptor)
    field_index = field_index_for(descriptor)
    [
      "def _write_one(record, writer, context, filters)\n",
      "  writer.push_object\n",
      json_indexed_filtered_body(descriptor, field_index, indent: 2),
      "  writer.pop\n",
      "end\n\n",
      json_serialize_many_bench
    ].join
  end

  def emit_indexed_single_path_hash(descriptor)
    field_index = field_index_for(descriptor)
    [
      "def _to_hash(record, context, filters)\n",
      "  result = {}\n",
      hash_indexed_filtered_body(descriptor, field_index, indent: 2),
      "  result\n",
      "end\n\n",
      hash_serialize_many_bench
    ].join
  end

  def json_indexed_filtered_body(descriptor, field_index, indent:)
    pad = " " * indent
    body = +""
    descriptor.attributes.each do |a|
      idx = field_index.fetch(a.name)
      body << pad << "unless filters.drops?(#{idx})\n"
      body << pad << "  writer.push_value(record._read_attribute(\"#{a.source}\"), \"#{a.name}\")\n"
      body << pad << "end\n"
    end
    descriptor.associations.each do |assoc|
      body << emit_indexed_assoc_json_filtered(assoc, field_index, indent: indent)
    end
    body
  end

  def hash_indexed_filtered_body(descriptor, field_index, indent:)
    pad = " " * indent
    body = +""
    descriptor.attributes.each do |a|
      idx = field_index.fetch(a.name)
      body << pad << "unless filters.drops?(#{idx})\n"
      body << pad << "  result[\"#{a.name}\"] = record._read_attribute(\"#{a.source}\")\n"
      body << pad << "end\n"
    end
    descriptor.associations.each do |assoc|
      body << emit_indexed_assoc_hash_filtered(assoc, field_index, indent: indent)
    end
    body
  end

  def emit_indexed_assoc_json_filtered(assoc, field_index, indent:)
    pad = " " * indent
    idx = field_index.fetch(assoc.name)
    case assoc.kind
    when :has_one
      pad + "unless filters.drops?(#{idx})\n" +
        pad + "  value = record.#{assoc.source}\n" +
        pad + "  if value.nil?\n" +
        pad + "    writer.push_value(nil, \"#{assoc.name}\")\n" +
        pad + "  else\n" +
        pad + "    writer.push_key(\"#{assoc.name}\")\n" +
        pad + "    @#{assoc.name}_serializer._write_one(value, writer, context, filters.child(:#{assoc.source}))\n" +
        pad + "  end\n" +
        pad + "end\n"
    when :has_many
      pad + "unless filters.drops?(#{idx})\n" +
        pad + "  child_filter = filters.child(:#{assoc.source})\n" +
        pad + "  writer.push_array(\"#{assoc.name}\")\n" +
        pad + "  record.#{assoc.source}.each do |element|\n" +
        pad + "    @#{assoc.name}_serializer._write_one(element, writer, context, child_filter)\n" +
        pad + "  end\n" +
        pad + "  writer.pop\n" +
        pad + "end\n"
    end
  end

  def emit_indexed_assoc_hash_filtered(assoc, field_index, indent:)
    pad = " " * indent
    idx = field_index.fetch(assoc.name)
    case assoc.kind
    when :has_one
      pad + "unless filters.drops?(#{idx})\n" +
        pad + "  value = record.#{assoc.source}\n" +
        pad + "  result[\"#{assoc.name}\"] = if value.nil?\n" +
        pad + "    nil\n" +
        pad + "  else\n" +
        pad + "    @#{assoc.name}_serializer._to_hash(value, context, filters.child(:#{assoc.source}))\n" +
        pad + "  end\n" +
        pad + "end\n"
    when :has_many
      pad + "unless filters.drops?(#{idx})\n" +
        pad + "  child_filter = filters.child(:#{assoc.source})\n" +
        pad + "  result[\"#{assoc.name}\"] = record.#{assoc.source}.map { |element| " \
                "@#{assoc.name}_serializer._to_hash(element, context, child_filter) }\n" +
        pad + "end\n"
    end
  end

  def field_index_for(descriptor)
    h = {}
    fields = descriptor.attributes + descriptor.method_attributes + descriptor.associations
    fields.each_with_index { |f, i| h[f.name] = i }
    h
  end
end

# ---- Per-cell instance builder ---------------------------------------------

# Walks the Descriptor tree depth-first, yielding each unique Descriptor
# exactly once (identity-keyed). Mirrors `Compiler#cache_descendants`'s
# walk shape so the overlay applies to the same set of classes the
# `CompileCache` populated.
def each_unique_descriptor(descriptor)
  seen = {}
  stack = [descriptor]
  until stack.empty?
    d = stack.pop
    next if seen[d.__id__]
    seen[d.__id__] = true
    yield d
    d.associations.each { |a| stack.push(a.descriptor) }
  end
end

# Compiles a fresh class tree for `descriptor` with our own `CompileCache`
# threaded through, then walks the tree and applies the cell-specific
# overlay to each class. Returns a fresh root-class instance ready for
# `_serialize_many_bench(records, filter)`.
#
# Compile is a pure function per `docs/compilation.md`, so each cell gets
# an independent class tree — no method-cache contamination across cells.
def compile_cell_instance(descriptor, cell_name:, output:)
  cache = SerializersCodeGen::CompileCache.new
  config = SerializersCodeGen::Config.new
  root = SerializersCodeGen::Compiler.new(descriptor, output: output, config: config, cache: cache).compile
  each_unique_descriptor(descriptor) do |d|
    klass = cache.get(d)
    src = Overlay.emit_for(descriptor: d, cell_name: cell_name, output: output)
    klass.module_eval(src, "(filter_experiments_bench: #{d.name}/#{output}/#{cell_name})", 1)
  end
  root.new(descriptor: descriptor)
end

# Compiles the reference instance — the filter-machinery-absent variant
# identical to the phase-1 emit body per `docs/filters.md § Experiment
# design § Reference row`. Adds a `_serialize_many_ref` entry that calls
# the standard `_write_one(r, writer, nil, nil)` directly so the
# `serialize_many` `raise NotImplementedError if filters` gate is bypassed
# at zero filter cost (the standard body forwards `filters` to children
# but never inspects it).
def compile_reference_instance(descriptor, output:)
  klass = SerializersCodeGen.compile(descriptor, output: output)
  src = if output == :json
    "def _serialize_many_ref(records)\n" \
      "  writer = Oj::StringWriter.new(mode: :rails)\n" \
      "  writer.push_array\n" \
      "  records.each { |r| _write_one(r, writer, nil, nil) }\n" \
      "  writer.pop\n" \
      "  writer.to_s.chomp\n" \
      "end\n"
  else
    "def _serialize_many_ref(records)\n" \
      "  records.map { |r| _to_hash(r, nil, nil) }\n" \
      "end\n"
  end
  # Apply the helper to every unique class in the tree so any back-edge
  # call (none today, but keeps the shape symmetric with the cell-overlay
  # walk) finds the helper available on each class.
  cache = SerializersCodeGen::CompileCache.new
  SerializersCodeGen::Compiler.new(descriptor, output: output, config: SerializersCodeGen::Config.new, cache: cache).compile
  each_unique_descriptor(descriptor) do |d|
    cache.get(d).module_eval(src)
  end
  klass.module_eval(src)
  klass.new(descriptor: descriptor)
end

# ---- Fixtures --------------------------------------------------------------

WIDE_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "FilterExperimentsWidePostSerializer",
  models: [FilterBench::WidePost],
  attributes: [
    SerializersCodeGen::Attribute.new(name: :id, source: :id),
    *WIDE_ATTRIBUTE_NAMES.map { |n| SerializersCodeGen::Attribute.new(name: n.to_sym, source: n.to_sym) }
  ],
  method_attributes: [],
  associations: []
)

GRAPH_AUTHOR_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "FilterExperimentsAuthorSerializer",
  models: [FilterBench::Author],
  attributes: [
    SerializersCodeGen::Attribute.new(name: :id, source: :id),
    SerializersCodeGen::Attribute.new(name: :name, source: :name),
    SerializersCodeGen::Attribute.new(name: :email, source: :email)
  ],
  method_attributes: [],
  associations: []
)

GRAPH_COMMENT_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "FilterExperimentsCommentSerializer",
  models: [FilterBench::Comment],
  attributes: [
    SerializersCodeGen::Attribute.new(name: :id, source: :id),
    SerializersCodeGen::Attribute.new(name: :body, source: :body)
  ],
  method_attributes: [],
  associations: []
)

# Medium graph per `docs/filters.md § Matrix`: ~5 Attributes + 2 has_one
# + 1 has_many (~10 children given 5 comments per post).
GRAPH_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "FilterExperimentsPostSerializer",
  models: [FilterBench::Post],
  attributes: [
    SerializersCodeGen::Attribute.new(name: :id, source: :id),
    SerializersCodeGen::Attribute.new(name: :title, source: :title),
    SerializersCodeGen::Attribute.new(name: :body, source: :body),
    SerializersCodeGen::Attribute.new(name: :views, source: :views),
    SerializersCodeGen::Attribute.new(name: :published, source: :published)
  ],
  method_attributes: [],
  associations: [
    SerializersCodeGen::Association.new(name: :author, kind: :has_one, descriptor: GRAPH_AUTHOR_DESCRIPTOR),
    SerializersCodeGen::Association.new(name: :first_comment, kind: :has_one, descriptor: GRAPH_COMMENT_DESCRIPTOR),
    SerializersCodeGen::Association.new(name: :comments, kind: :has_many, descriptor: GRAPH_COMMENT_DESCRIPTOR)
  ]
)

# Shallow `:only` for fixture #2 — 20 of 70 attribute names, mixed across
# the four primitive types so the filter doesn't trivially cluster.
WIDE_ONLY_NAMES = (
  WIDE_STRING_NAMES.first(8) +
  WIDE_INTEGER_NAMES.first(6) +
  WIDE_BOOLEAN_NAMES.first(3) +
  WIDE_DECIMAL_NAMES.first(2) +
  WIDE_DATE_NAMES.first(1)
).map(&:to_sym).freeze

FIXTURES = [
  {
    name: "wide_flat_none",
    descriptor: WIDE_DESCRIPTOR,
    records: WIDE_RECORDS,
    filter_hash: nil,
    sizes: [50, 2300]
  },
  {
    name: "wide_flat_shallow_only",
    descriptor: WIDE_DESCRIPTOR,
    records: WIDE_RECORDS,
    filter_hash: {only: WIDE_ONLY_NAMES},
    sizes: [1, 50, 2300]
  },
  {
    name: "medium_graph_none",
    descriptor: GRAPH_DESCRIPTOR,
    records: GRAPH_RECORDS,
    filter_hash: nil,
    sizes: [50, 2300]
  },
  {
    name: "medium_graph_shallow_only",
    descriptor: GRAPH_DESCRIPTOR,
    records: GRAPH_RECORDS,
    filter_hash: {only: %i[id title author]},
    sizes: [1, 50, 2300]
  },
  {
    name: "medium_graph_deep_nested",
    descriptor: GRAPH_DESCRIPTOR,
    records: GRAPH_RECORDS,
    filter_hash: {
      only: %i[id title author comments],
      author: {only: %i[id name]},
      comments: {except: %i[id]}
    },
    sizes: [1, 50, 2300]
  }
].freeze

# ---- Cell construction + Filter wrapping -----------------------------------

# Builds reference + one Generated Class instance per cell for the given
# Descriptor / output mode. Returns a Hash keyed by `:reference` and
# every name in +CELL_NAMES+; each value is a Generated Class instance
# ready for `_serialize_many_*(...)`.
def build_fixture_instances(descriptor, output:)
  instances = {reference: compile_reference_instance(descriptor, output: output)}
  CELL_NAMES.each do |cell_name|
    instances[cell_name] = compile_cell_instance(descriptor, cell_name: cell_name, output: output)
  end
  instances
end

# Builds a Filter object for one cell at run time. Mirrors what the
# production public entry point would do: normalize the caller's Hash once
# into a representation-specific Filter object. `nil` / `{}` collapse to
# the `NoneFilter` singleton per `docs/filters.md § Public shape`. The
# +indexed_single_path+ cell additionally requires the Descriptor to
# resolve Field-name → integer index at construction.
def build_filter(cell_name, descriptor, filter_hash)
  return NoneFilter::INSTANCE if filter_hash.nil? || filter_hash.empty?
  case cell_name
  when :hash_wrapper_single_path, :hash_wrapper_dual_path
    HashWrapperFilter.new(filter_hash)
  when :set_index_single_path, :set_index_dual_path
    SetIndexFilter.new(filter_hash)
  when :indexed_single_path
    IndexedFilter.build(descriptor, filter_hash)
  end
end

# ---- Byte-equivalence pre-flight -------------------------------------------
#
# Per the issue's "Byte-equivalence pre-flight" criterion: before each
# fixture's timed loop, assert that all 4 cells produce identical output.
# For no-filter fixtures (#1, #3) the reference must also match — the
# cells run with `NoneFilter` and emit the same fields as the unmodified
# phase-1 body. For filter-present fixtures (#2, #4, #5) the reference
# diverges by design — it is the filter-machinery-absent ceiling per
# `docs/filters.md § Experiment design § Reference row`. If any cell
# diverges from the others, the bench halts before measurement (output
# equivalence is mandatory or the comparison is meaningless).
def assert_byte_equivalent!(label, fixture, instances)
  records = fixture[:records].first(50)
  descriptor = fixture[:descriptor]
  cell_outputs = {}
  CELL_NAMES.each do |cell_name|
    inst = instances[cell_name]
    filter = build_filter(cell_name, descriptor, fixture[:filter_hash])
    cell_outputs[cell_name] = inst._serialize_many_bench(records, filter)
  end
  first_name, first_out = cell_outputs.first
  cell_outputs.each do |cell_name, out|
    next if out == first_out
    abort "Pre-flight FAILED [#{label}/#{fixture[:name]}]: cell #{cell_name} diverges from #{first_name}"
  end
  if fixture[:filter_hash].nil?
    reference_out = instances[:reference]._serialize_many_ref(records)
    unless reference_out == first_out
      abort "Pre-flight FAILED [#{label}/#{fixture[:name]}]: reference diverges from cells (no-filter fixture)"
    end
    puts "  pre-flight OK: #{CELL_NAMES.size} cells + reference produce identical output (no-filter fixture)"
  else
    puts "  pre-flight OK: #{CELL_NAMES.size} cells produce identical output (reference is filter-machinery-absent ceiling)"
  end
end

# ---- Bench loop ------------------------------------------------------------

def run_fixture(fixture, output:, label:)
  puts "============================================="
  puts "[#{label}] Fixture: #{fixture[:name]}"
  puts "  descriptor: #{fixture[:descriptor].name}"
  puts "  filter:     #{fixture[:filter_hash].inspect}"
  puts "  sizes:      #{fixture[:sizes].inspect}"
  puts "============================================="
  instances = build_fixture_instances(fixture[:descriptor], output: output)
  assert_byte_equivalent!(label, fixture, instances)
  puts

  descriptor = fixture[:descriptor]
  fixture[:sizes].each do |size|
    records = fixture[:records].first(size)
    puts "--- ips: #{label}/#{fixture[:name]} size=#{size} ---"
    Benchmark.ips do |x|
      x.config(time: IPS_TIME, warmup: IPS_WARMUP)
      x.report("reference") { instances[:reference]._serialize_many_ref(records) }
      CELL_NAMES.each do |cell_name|
        inst = instances[cell_name]
        filter_hash = fixture[:filter_hash]
        x.report(cell_name.to_s) do
          filter = build_filter(cell_name, descriptor, filter_hash)
          inst._serialize_many_bench(records, filter)
        end
      end
      x.compare!
    end
    puts

    puts "--- allocations: #{label}/#{fixture[:name]} size=#{size} (1 call each) ---"
    ref_report = MemoryProfiler.report { instances[:reference]._serialize_many_ref(records) }
    puts "  %-40s %8d allocs %12d bytes" % ["reference", ref_report.total_allocated, ref_report.total_allocated_memsize]
    CELL_NAMES.each do |cell_name|
      inst = instances[cell_name]
      filter_hash = fixture[:filter_hash]
      report = MemoryProfiler.report do
        filter = build_filter(cell_name, descriptor, filter_hash)
        inst._serialize_many_bench(records, filter)
      end
      puts "  %-40s %8d allocs %12d bytes" % [cell_name.to_s, report.total_allocated, report.total_allocated_memsize]
    end
    puts
  end
end

# ---- Environment -----------------------------------------------------------

puts "Ruby:    #{RUBY_DESCRIPTION}"
puts "AR:      #{ActiveRecord::VERSION::STRING}"
puts "YJIT:    #{(defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?) ? "on" : "off"}"
puts "IPS:     time=#{IPS_TIME}s warmup=#{IPS_WARMUP}s"
puts "Cells:   #{CELL_NAMES.join(", ")} + reference"
puts
unless defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
  warn "WARNING: YJIT is not enabled. Re-run with --yjit for production-target numbers."
  puts
end

# ---- Canonical JSON-mode run -----------------------------------------------

FIXTURES.each do |fixture|
  run_fixture(fixture, output: :json, label: "json")
end

# ---- Hash-mode parity check (fixture #2 only) ------------------------------
#
# Per `docs/filters.md § Output mode coverage`: re-run one fixture
# (wide-flat x shallow `:only`) in `:hash` mode to confirm the same cell
# wins. If it doesn't, S13.3 halts the verdict and investigates the
# divergence per `#55` user story 14 — divergence would signal that the
# Filter object is leaking output-mode coupling. The bench just measures;
# the verdict + halt logic lives in the results-doc backfill.

puts "============================================="
puts "Hash-mode parity check"
puts "============================================="
parity_fixture = FIXTURES.find { |f| f[:name] == "wide_flat_shallow_only" }
run_fixture(parity_fixture, output: :hash, label: "hash")
