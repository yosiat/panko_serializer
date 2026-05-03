# frozen_string_literal: true

# Exploration: writer pooling — reuse a single Oj::StringWriter across calls
# instead of allocating one per serialize_one / serialize_many.
#
# Question:
#   The deferred.md note ("Writer pooling") flags this as "probably negligible
#   on the hot path; only fix if benchmarks show it." This script measures
#   whether benchmarks DO show it.
#
# Strategy:
#   1. Pure microbench — Oj::StringWriter.new(mode: :rails) vs writer.reset
#      throughput in isolation. Sets the upper bound on what pooling can save.
#   2. End-to-end — serialize_one and serialize_many with a fresh writer per
#      call vs a thread-local pooled writer. Two hand-written generated-class
#      shapes mirroring what the library emits today, modulo the writer source.
#
# Run (YJIT, mirroring production):
#   bundle exec ruby --yjit docs/research/writer_pool_exploration.rb

require "active_record"
require "sqlite3"
require "oj"
require "benchmark/ips"
require "memory_profiler"

unless defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
  warn "WARNING: YJIT not enabled. Run with `ruby --yjit` for production-shape numbers."
end

# ---- Minimal AR setup -------------------------------------------------------

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :posts, force: true do |t|
    t.string :title
    t.string :body
    t.integer :views
    t.boolean :published
  end
end

class Post < ActiveRecord::Base; end
Post.define_attribute_methods

POSTS_50 = 50.times.map do |i|
  Post.create!(title: "Post ##{i}", body: "Body of #{i}.", views: i, published: i.even?)
end
POSTS_2300 = Post.all.to_a + (51..2299).map do |i|
  Post.create!(title: "Post ##{i}", body: "Body of #{i}.", views: i, published: i.even?)
end
POST = POSTS_50.first

# ---- Two emit shapes: Fresh (current) and Pooled (proposed) -----------------
#
# The two classes emit byte-identical output. The ONLY difference is the
# writer-acquisition line:
#
#   Fresh:  writer = Oj::StringWriter.new(mode: :rails)
#   Pooled: writer = (Thread.current[:_scg_writer] ||= Oj::StringWriter.new(mode: :rails))
#           writer.reset
#
# `_write_one` and the inner emit lines are copy-paste identical to what the
# library generates for the simple-shape Descriptor (5 column attributes).

class FreshSerializer
  def serialize_one(record)
    writer = Oj::StringWriter.new(mode: :rails)
    _write_one(record, writer)
    result = writer.to_s
    result.chomp!
    result
  end

  def serialize_many(records)
    writer = Oj::StringWriter.new(mode: :rails)
    writer.push_array
    records.each { |r| _write_one(r, writer) }
    writer.pop
    result = writer.to_s
    result.chomp!
    result
  end

  def _write_one(record, writer)
    writer.push_object
    writer.push_value(record._read_attribute("id"), "id")
    writer.push_value(record._read_attribute("title"), "title")
    writer.push_value(record._read_attribute("body"), "body")
    writer.push_value(record._read_attribute("views"), "views")
    writer.push_value(record._read_attribute("published"), "published")
    writer.pop
  end
end

class PooledSerializer
  def serialize_one(record)
    writer = (Thread.current[:_scg_writer] ||= Oj::StringWriter.new(mode: :rails))
    writer.reset
    _write_one(record, writer)
    result = writer.to_s
    result.chomp!
    result
  end

  def serialize_many(records)
    writer = (Thread.current[:_scg_writer] ||= Oj::StringWriter.new(mode: :rails))
    writer.reset
    writer.push_array
    records.each { |r| _write_one(r, writer) }
    writer.pop
    result = writer.to_s
    result.chomp!
    result
  end

  def _write_one(record, writer)
    writer.push_object
    writer.push_value(record._read_attribute("id"), "id")
    writer.push_value(record._read_attribute("title"), "title")
    writer.push_value(record._read_attribute("body"), "body")
    writer.push_value(record._read_attribute("views"), "views")
    writer.push_value(record._read_attribute("published"), "published")
    writer.pop
  end
end

FRESH = FreshSerializer.new
POOLED = PooledSerializer.new

# Output-parity guard — abort if the two shapes diverge.
fresh_one = FRESH.serialize_one(POST)
pooled_one = POOLED.serialize_one(POST)
abort "serialize_one diverged: #{fresh_one.inspect} vs #{pooled_one.inspect}" if fresh_one != pooled_one
fresh_many = FRESH.serialize_many(POSTS_50)
pooled_many = POOLED.serialize_many(POSTS_50)
abort "serialize_many diverged" if fresh_many != pooled_many
puts "Output parity verified."
puts "Sample serialize_one: #{fresh_one}"
puts

# ---- Bench helpers ----------------------------------------------------------

def measure(label, &block)
  block.call

  ips_report = Benchmark.ips do |x|
    x.config(time: 5, warmup: 2, quiet: true)
    x.report(label, &block)
  end
  entry = ips_report.entries.first
  rate = entry.stats.central_tendency
  err = entry.stats.error_percentage

  GC.disable
  mem = MemoryProfiler.report(&block)
  GC.enable
  GC.start

  rate_s = if rate >= 1_000_000 then "%.2fM" % (rate / 1_000_000)
  elsif rate >= 1_000 then "%.2fK" % (rate / 1_000)
  else "%.2f" % rate
  end

  puts "%-58s %10s i/s ±%5.2f%%  %8d allocs  %8d retained" %
    [label, rate_s, err, mem.total_allocated, mem.total_retained]
end

# ---- 1. Pure microbench -----------------------------------------------------
# Upper bound on what pooling can save: cost of one `Oj::StringWriter.new(mode:
# :rails)` vs cost of one `writer.reset` on a pre-allocated instance.
puts "=== 1. Pure writer-acquisition microbench ==="
puts

POOL = Oj::StringWriter.new(mode: :rails)

measure("alloc fresh writer (.new + .to_s)") do
  w = Oj::StringWriter.new(mode: :rails)
  w.push_object
  w.push_value(1, "id")
  w.pop
  w.to_s
end

measure("pooled writer (.reset + .to_s)") do
  POOL.reset
  POOL.push_object
  POOL.push_value(1, "id")
  POOL.pop
  POOL.to_s
end

puts

# ---- 2. End-to-end: serialize_one (single record) ---------------------------
# Fresh-writer-per-call is the worst case for pooling — every call pays the
# allocation, so this is where pooling should shine if anywhere.
puts "=== 2. serialize_one (1 record, AR specialized path) ==="
puts

measure("fresh /serialize_one") { FRESH.serialize_one(POST) }
measure("pooled/serialize_one") { POOLED.serialize_one(POST) }

puts

# ---- 3. End-to-end: serialize_many ------------------------------------------
# One writer covers N records, so pooling saves 1 alloc per call regardless of
# size. The relative gain shrinks as N grows.
puts "=== 3. serialize_many (collection) ==="
puts

[50, 2300].each do |n|
  records = (n == 50) ? POSTS_50 : POSTS_2300
  measure("fresh /serialize_many size=#{n}") { FRESH.serialize_many(records) }
  measure("pooled/serialize_many size=#{n}") { POOLED.serialize_many(records) }
  puts
end
