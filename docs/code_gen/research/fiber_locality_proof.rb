# frozen_string_literal: true

# Proves the locality semantics of Thread#[] vs Thread#thread_variable_*
# without depending on async/Falcon. Uses raw Fiber.new + Fiber#resume so
# fiber switches happen at deterministic points we control. If two fibers
# in the SAME thread can't see each other's writes, the storage is
# fiber-local. If they can, it's thread-local.
#
# Run: bundle exec ruby docs/research/fiber_locality_proof.rb

require "oj"

puts "Ruby: #{RUBY_DESCRIPTION}"
puts

# ---- Test 1: Thread.current[:k] (the `Thread#[]` API) ----------------------
puts "=== Test 1: Thread.current[:k] (the `Thread#[]` API) ==="

Thread.current[:probe] = "main"

f_a = Fiber.new do
  Thread.current[:probe] = "fiber_a"
  Fiber.yield
  puts "  fiber_a, after fiber_b ran, sees Thread.current[:probe] = #{Thread.current[:probe].inspect}"
end

f_b = Fiber.new do
  puts "  fiber_b, before any write,    sees Thread.current[:probe] = #{Thread.current[:probe].inspect}"
  Thread.current[:probe] = "fiber_b"
end

f_a.resume  # fiber_a writes "fiber_a", yields
f_b.resume  # fiber_b reads (sees what?), writes "fiber_b", returns
f_a.resume  # fiber_a resumes — does it see its own "fiber_a", or "fiber_b"?

puts "  main thread,                   sees Thread.current[:probe] = #{Thread.current[:probe].inspect}"
puts "  Verdict: Thread#[] is FIBER-LOCAL (each fiber + main has its own slot)."
puts

# ---- Test 2: Thread.current.thread_variable_get/set ------------------------
puts "=== Test 2: Thread.current.thread_variable_* (the TRUE thread-local API) ==="

Thread.current.thread_variable_set(:probe, "main")

f_a = Fiber.new do
  Thread.current.thread_variable_set(:probe, "fiber_a")
  Fiber.yield
  puts "  fiber_a, after fiber_b ran, sees thread_variable_get(:probe) = #{Thread.current.thread_variable_get(:probe).inspect}"
end

f_b = Fiber.new do
  puts "  fiber_b, before any write,    sees thread_variable_get(:probe) = #{Thread.current.thread_variable_get(:probe).inspect}"
  Thread.current.thread_variable_set(:probe, "fiber_b")
end

f_a.resume
f_b.resume
f_a.resume

puts "  main thread,                   sees thread_variable_get(:probe) = #{Thread.current.thread_variable_get(:probe).inspect}"
puts "  Verdict: thread_variable_* is TRUE THREAD-LOCAL — fibers SHARE the slot."
puts

# ---- Test 3: Pooled writer scenario, two fibers interleaved ----------------
# This is the user's worry: "multiple concurrent fibers doing serialization
# will overwrite the same string-writer." Each fiber yields WITH AN OPEN
# WRITER FRAME. If Thread.current[:k] is fiber-local, each fiber gets its
# OWN writer and outputs are correct. If it weren't, fiber_b would clobber
# fiber_a's mid-emit state.

puts "=== Test 3: Pooled writer (Thread.current), two fibers interleaved ==="

def pooled_serialize_with_yield(record)
  writer = (Thread.current[:_scg_writer] ||= Oj::StringWriter.new(mode: :rails))
  writer.reset
  writer.push_object
  writer.push_value(record[:id], "id")
  Fiber.yield  # <-- yields with frame OPEN
  writer.push_value(record[:name], "name")
  writer.pop
  result = writer.to_s
  result.chomp!
  result
end

results = {}
f_a = Fiber.new { results[:a] = pooled_serialize_with_yield(id: 1, name: "alice") }
f_b = Fiber.new { results[:b] = pooled_serialize_with_yield(id: 2, name: "bob") }

f_a.resume  # alice: open obj, push id=1, yield (frame open)
f_b.resume  # bob:   open obj, push id=2, yield (frame open) — DIFFERENT writer if fiber-local
f_a.resume  # alice: push name, pop, to_s → results[:a]
f_b.resume  # bob:   push name, pop, to_s → results[:b]

expected_a = '{"id":1,"name":"alice"}'
expected_b = '{"id":2,"name":"bob"}'
puts "  fiber_a result: #{results[:a].inspect}  (expected #{expected_a.inspect}) → #{(results[:a] == expected_a) ? "OK" : "CORRUPTED"}"
puts "  fiber_b result: #{results[:b].inspect}  (expected #{expected_b.inspect}) → #{(results[:b] == expected_b) ? "OK" : "CORRUPTED"}"

# Identity check: each fiber's writer object is distinct.
ids = []
f_id_a = Fiber.new { ids << Thread.current[:_scg_writer].object_id }
f_id_b = Fiber.new { ids << Thread.current[:_scg_writer].object_id }
f_id_a.resume
f_id_b.resume
puts "  writer.object_ids per fiber: #{ids.inspect} — distinct? #{ids.first != ids.last}"
puts

# ---- Test 4: Same scenario with thread_variable_* — provable corruption ----
puts "=== Test 4: Pooled writer (thread_variable_*) — the ACTUAL corruption case ==="

def thread_variable_serialize_with_yield(record)
  writer = Thread.current.thread_variable_get(:_scg_writer_tv)
  unless writer
    writer = Oj::StringWriter.new(mode: :rails)
    Thread.current.thread_variable_set(:_scg_writer_tv, writer)
  end
  writer.reset
  writer.push_object
  writer.push_value(record[:id], "id")
  Fiber.yield
  writer.push_value(record[:name], "name")
  writer.pop
  result = writer.to_s
  result.chomp!
  result
end

Thread.current.thread_variable_set(:_scg_writer_tv, nil)  # ensure cold
results2 = {}
f_a = Fiber.new do
  results2[:a] = thread_variable_serialize_with_yield(id: 1, name: "alice")
rescue => e
  results2[:a] = "RAISED: #{e.class}: #{e.message}"
end
f_b = Fiber.new do
  results2[:b] = thread_variable_serialize_with_yield(id: 2, name: "bob")
rescue => e
  results2[:b] = "RAISED: #{e.class}: #{e.message}"
end

f_a.resume
f_b.resume
begin
  f_a.resume
rescue => e
  results2[:a] = "RAISED on resume: #{e.class}: #{e.message}"
end
begin
  f_b.resume
rescue => e
  results2[:b] = "RAISED on resume: #{e.class}: #{e.message}"
end

puts "  fiber_a result: #{results2[:a].inspect}  → #{(results2[:a] == expected_a) ? "OK" : "CORRUPTED"}"
puts "  fiber_b result: #{results2[:b].inspect}  → #{(results2[:b] == expected_b) ? "OK" : "CORRUPTED"}"
