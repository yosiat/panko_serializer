# frozen_string_literal: true

# Benchmark ActiveRecord attribute access strategies for the serializers-code-gen
# library's specialized path.
#
# Run (YJIT — the production target):
#   bundle exec ruby --yjit ar_access_bench.rb
#
# Ruby 4.0.2 is assumed (mise.toml pins it). The script warns if YJIT isn't enabled.

require "active_record"
require "sqlite3"
require "benchmark/ips"
require "memory_profiler"
require "bigdecimal"
require "bigdecimal/util"
require "date"
require "time"

# ---- AR setup ---------------------------------------------------------------

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Schema.define do
  create_table :posts do |t|
    t.string   :title
    t.text     :body
    t.boolean  :published
    t.datetime :published_at
    t.date     :publish_date
    t.integer  :view_count
    t.decimal  :rating, precision: 10, scale: 2
    t.integer  :status, default: 0, null: false
  end
end

class Post < ActiveRecord::Base
  enum :status, { draft: 0, published: 1, archived: 2 }
end

# Force attribute-method generation up front so we don't measure
# first-call codegen inside the hot loop.
Post.define_attribute_methods

# ---- Fixtures ---------------------------------------------------------------

attrs = {
  title: "A short title",
  body: "A longer body with more words to serialize. " * 10,
  published: true,
  published_at: Time.now,
  publish_date: Date.today,
  view_count: 12_345,
  rating: BigDecimal("4.25"),
  status: "published"
}

Post.create!(**attrs)
PERSISTED     = Post.first
NON_PERSISTED = Post.new(**attrs)

# Column names as strings + symbols, frozen to match generated-code literals.
COLS = %w[id title body published published_at publish_date view_count rating status].map(&:freeze).freeze
COLS_SYM = COLS.map(&:to_sym).freeze

# Pre-resolve a type-cast callable per column for the "raw + manual cast" forms.
# This matches what Panko's old before_type_cast path did conceptually: read raw,
# cast manually in Ruby. For the bench we cast to the "useful" Ruby form that a
# type-cast read would yield.
CAST = {
  "id"           => ->(v) { v.to_i },
  "title"        => ->(v) { v },
  "body"         => ->(v) { v },
  "published"    => ->(v) { v == "t" || v == 1 || v == true },
  "published_at" => ->(v) { v.is_a?(String) ? Time.parse(v) : v },
  "publish_date" => ->(v) { v.is_a?(String) ? Date.parse(v) : v },
  "view_count"   => ->(v) { v.to_i },
  "rating"       => ->(v) { v.is_a?(String) ? v.to_d : v },
  # Enum column: raw before_type_cast gives the DB integer; we map it back.
  "status"       => ->(v) { { 0 => "draft", 1 => "published", 2 => "archived" }[v.to_i] }
}
CAST.freeze
CAST.each_value(&:freeze)

# ---- Access variants --------------------------------------------------------
#
# Each variant takes a record and reads ALL columns into a local array so the
# benchmark reflects a realistic "read every field" loop like a serializer does.
# Returning the array keeps the read live (not dead-code eliminated).

def via_method_dispatch(r)
  [r.id, r.title, r.body, r.published, r.published_at, r.publish_date, r.view_count, r.rating, r.status]
end

def via_read_attribute(r)
  [r.read_attribute("id"), r.read_attribute("title"), r.read_attribute("body"),
   r.read_attribute("published"), r.read_attribute("published_at"),
   r.read_attribute("publish_date"), r.read_attribute("view_count"),
   r.read_attribute("rating"), r.read_attribute("status")]
end

def via__read_attribute(r)
  [r._read_attribute("id"), r._read_attribute("title"), r._read_attribute("body"),
   r._read_attribute("published"), r._read_attribute("published_at"),
   r._read_attribute("publish_date"), r._read_attribute("view_count"),
   r._read_attribute("rating"), r._read_attribute("status")]
end

def via_attributes_hash(r)
  h = r.attributes
  [h["id"], h["title"], h["body"], h["published"], h["published_at"],
   h["publish_date"], h["view_count"], h["rating"], h["status"]]
end

def via_attributes_before_type_cast(r)
  h = r.attributes_before_type_cast
  [h["id"], h["title"], h["body"], h["published"], h["published_at"],
   h["publish_date"], h["view_count"], h["rating"], h["status"]]
end

def via_read_attr_before_type_cast(r)
  [r.read_attribute_before_type_cast("id"),
   r.read_attribute_before_type_cast("title"),
   r.read_attribute_before_type_cast("body"),
   r.read_attribute_before_type_cast("published"),
   r.read_attribute_before_type_cast("published_at"),
   r.read_attribute_before_type_cast("publish_date"),
   r.read_attribute_before_type_cast("view_count"),
   r.read_attribute_before_type_cast("rating"),
   r.read_attribute_before_type_cast("status")]
end

def via_bracket_string(r)
  [r["id"], r["title"], r["body"], r["published"], r["published_at"],
   r["publish_date"], r["view_count"], r["rating"], r["status"]]
end

def via_bracket_symbol(r)
  [r[:id], r[:title], r[:body], r[:published], r[:published_at],
   r[:publish_date], r[:view_count], r[:rating], r[:status]]
end

# "raw + manual re-cast" — the Panko-style trick.
def via_attrs_bt_cast(r)
  h = r.attributes_before_type_cast
  [CAST["id"].call(h["id"]),
   CAST["title"].call(h["title"]),
   CAST["body"].call(h["body"]),
   CAST["published"].call(h["published"]),
   CAST["published_at"].call(h["published_at"]),
   CAST["publish_date"].call(h["publish_date"]),
   CAST["view_count"].call(h["view_count"]),
   CAST["rating"].call(h["rating"]),
   CAST["status"].call(h["status"])]
end

def via_read_bt_cast(r)
  [CAST["id"].call(r.read_attribute_before_type_cast("id")),
   CAST["title"].call(r.read_attribute_before_type_cast("title")),
   CAST["body"].call(r.read_attribute_before_type_cast("body")),
   CAST["published"].call(r.read_attribute_before_type_cast("published")),
   CAST["published_at"].call(r.read_attribute_before_type_cast("published_at")),
   CAST["publish_date"].call(r.read_attribute_before_type_cast("publish_date")),
   CAST["view_count"].call(r.read_attribute_before_type_cast("view_count")),
   CAST["rating"].call(r.read_attribute_before_type_cast("rating")),
   CAST["status"].call(r.read_attribute_before_type_cast("status"))]
end

VARIANTS = {
  "method_dispatch"          => method(:via_method_dispatch),
  "read_attribute"           => method(:via_read_attribute),
  "_read_attribute"          => method(:via__read_attribute),
  "attributes[]"             => method(:via_attributes_hash),
  "attributes_before_type_cast[]" => method(:via_attributes_before_type_cast),
  "read_attribute_before_type_cast" => method(:via_read_attr_before_type_cast),
  "record['col']"            => method(:via_bracket_string),
  "record[:col]"             => method(:via_bracket_symbol),
  "attrs_bt + manual cast"   => method(:via_attrs_bt_cast),
  "read_bt + manual cast"    => method(:via_read_bt_cast)
}.freeze

# ---- Correctness spot-check -------------------------------------------------
# Print what each form returns for a persisted record, so we can confirm
# type-casting (and especially enum) behavior in the report.

def dump_correctness(label, rec)
  puts "=== correctness (#{label}) ==="
  VARIANTS.each do |name, m|
    vals = m.call(rec)
    # Compact representation
    puts "%-32s => %s" % [name, vals.map { |v| v.inspect[0, 40] }.join(" | ")]
  end
  puts
end

# ---- YJIT / ZJIT status -----------------------------------------------------

def jit_status
  parts = []
  parts << "YJIT=#{(defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?) ? "on" : "off"}"
  parts << "ZJIT=#{(defined?(RubyVM::ZJIT) && RubyVM::ZJIT.respond_to?(:enabled?) && RubyVM::ZJIT.enabled?) ? "on" : "off"}"
  parts.join(" ")
end

puts "Ruby:   #{RUBY_DESCRIPTION}"
puts "AR:     #{ActiveRecord::VERSION::STRING}"
puts "JITs:   #{jit_status}"
puts "Cols:   #{COLS.join(", ")}"
puts

unless defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
  warn "WARNING: YJIT is not enabled. Re-run with `--yjit` for production-target numbers."
end
puts

dump_correctness("persisted",     PERSISTED)
dump_correctness("non-persisted", NON_PERSISTED)

# ---- Benchmark --------------------------------------------------------------

def run_ips(label, record)
  puts "=== ips: #{label} ==="
  Benchmark.ips do |x|
    x.config(warmup: 3, time: 5)
    VARIANTS.each do |name, m|
      x.report(name) { m.call(record) }
    end
    x.compare!
  end
  puts
end

run_ips("persisted",     PERSISTED)
run_ips("non-persisted", NON_PERSISTED)

# ---- Memory profile ---------------------------------------------------------

def run_memprof(label, record)
  puts "=== allocations (#{label}) — 1 call each ==="
  VARIANTS.each do |name, m|
    report = MemoryProfiler.report { m.call(record) }
    puts "%-32s %6d allocs  %8d bytes" % [name, report.total_allocated, report.total_allocated_memsize]
  end
  puts
end

run_memprof("persisted",     PERSISTED)
run_memprof("non-persisted", NON_PERSISTED)
