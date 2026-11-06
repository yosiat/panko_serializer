# frozen_string_literal: true

# Memory check for the reused JSON writers, not a speed benchmark. THREADS
# long-lived threads (like an app server's pool) each serialize one large
# array per serializer class, then a few small ones, and stay alive. Prints
# the RSS growth while they live. A writer pool that kept large buffers shows
# roughly THREADS x SERIALIZERS x the large output size here.
#
# Linux only (reads /proc). Run on the allocator you deploy with, e.g. with
# jemalloc preloaded and MALLOC_CONF=dirty_decay_ms:0,muzzy_decay_ms:0 so only
# live memory counts:
#
#   bundle exec appraisal 8.1.0 ruby benchmarks/writer_retention.rb
#
# Knobs: THREADS (16), ROWS (20_000, about 13 MB of JSON), SERIALIZERS (3).

require "active_record"
require "panko_serializer"

threads = Integer(ENV.fetch("THREADS", "16"))
rows = Integer(ENV.fetch("ROWS", "20000"))
serializer_count = Integer(ENV.fetch("SERIALIZERS", "3"))
fields = (1..20).map { |i| :"field_#{i}" }

def rss_mb
  File.read("/proc/self/status")[/VmRSS:\s+(\d+)/, 1].to_i / 1024.0
end

Row = Struct.new(*fields)
serializers = Array.new(serializer_count) do |i|
  Class.new(Panko::Serializer) { attributes(*fields) }.tap { |klass| Object.const_set(:"RowSerializer#{i}", klass) }
end
large = Array.new(rows) { |r| Row.new(*fields.map { |f| "#{f}-#{r}-#{"x" * 10}" }) }
small = large.first(50)
serializers.each { |klass| Panko::ArraySerializer.new(small, each_serializer: klass).to_json }

GC.start
baseline = rss_mb
large_bytes = 0
workers = Array.new(threads) do
  Thread.new do
    serializers.each do |klass|
      large_bytes = Panko::ArraySerializer.new(large, each_serializer: klass).to_json.bytesize
    end
    5.times { serializers.each { |klass| Panko::ArraySerializer.new(small, each_serializer: klass).to_json } }
    sleep 3
  end
end
sleep 0.1 until workers.all? { |t| t.status == "sleep" || !t.alive? }
4.times { GC.start }
sleep 1
held = rss_mb - baseline
workers.each(&:join)

puts "Ruby:    #{RUBY_DESCRIPTION}"
# respond_to? keeps the script runnable against older revisions for an A/B.
max_bytes = Panko::Config.respond_to?(:writer_pool_max_bytes) ? Panko::Config.writer_pool_max_bytes : "n/a"
puts format("threads=%d serializers=%d large_output=%.1fMB writer_pool_max_bytes=%s",
  threads, serializer_count, large_bytes / 1e6, max_bytes)
puts format("RSS growth while threads are alive: %+.0f MB", held)
