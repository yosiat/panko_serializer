# frozen_string_literal: true

require_relative "setup"
require_relative "datasets"

# Frozen Data value carrying every env knob parsed once at harness load.
# Read by `benchmark` / `benchmark_with_records` / `benchmark_scenario` to
# decide which rows to measure and how to measure them. Documented at
# docs/benchmarks.md § Harness.
BenchmarkConfig = Data.define(:size, :bench, :target, :profile, :ips_time, :ips_warmup) do
  # Effective size list for this run: a one-element array when SIZE=n was
  # set, otherwise BENCHMARK_SIZES.
  #
  # @return [Array<Integer>]
  def sizes
    size ? [size] : BENCHMARK_SIZES
  end
end

# Singleton config for the current process — built once from ENV before any
# benchmark runs. The harness internals read from it directly rather than
# threading it as an arg through every helper, mirroring Panko's bench harness
# shape (per docs/benchmarks.md § Harness).
BENCHMARK_CONFIG = BenchmarkConfig.new(
  size: (ENV["SIZE"] && !ENV["SIZE"].empty?) ? ENV["SIZE"].to_i : nil,
  bench: (ENV["BENCH"] && !ENV["BENCH"].empty?) ? ENV["BENCH"] : nil,
  target: (ENV["TARGET"] && !ENV["TARGET"].empty?) ? ENV["TARGET"] : nil,
  profile: ENV["PROFILE"],
  ips_time: (ENV["IPS_TIME"] || "5").to_f,
  ips_warmup: (ENV["IPS_WARMUP"] || "2").to_f
)

puts "Ruby:    #{RUBY_DESCRIPTION}"
puts "AR:      #{ActiveRecord::VERSION::STRING}"
puts "YJIT:    #{(defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?) ? "on" : "off"}"
puts "PROFILE: #{BENCHMARK_CONFIG.profile || "ips+memory"}"
puts "SIZES:   #{BENCHMARK_CONFIG.sizes.inspect}"
puts "FILTERS: BENCH=#{BENCHMARK_CONFIG.bench.inspect}  TARGET=#{BENCHMARK_CONFIG.target.inspect}"
puts

# StackProf is started once at harness load when PROFILE=cpu and the combined
# profile is dumped at exit. Per-block start/stop is too granular in
# fast-iteration mode (each report runs for IPS_TIME seconds) and yields a
# noisy profile.
if BENCHMARK_CONFIG.profile == "cpu"
  StackProf.start(mode: :cpu, raw: true, interval: 1000)
  at_exit do
    StackProf.stop
    puts
    puts "=== StackProf (cpu, interval=1000us) ==="
    StackProf::Report.new(StackProf.results).print_text(false, 25)
  end
end

# Formats an ips rate with thousands/millions suffix, narrow enough to stack
# in a single column.
#
# @param rate [Float]
# @return [String]
def benchmark_format_rate(rate)
  if rate >= 1_000_000
    "%.2fM" % (rate / 1_000_000.0)
  elsif rate >= 1_000
    "%.2fK" % (rate / 1_000.0)
  else
    "%.2f" % rate
  end
end

# Runs +block+ once under benchmark-ips for ips, then once under
# MemoryProfiler for allocs + retained, and prints one row of output. Returns
# nothing meaningful — the harness is stdout-driven (per docs/benchmarks.md §
# Baseline workflow). When BENCH=<substr> is set and the label doesn't
# case-insensitively contain it, the row is silently skipped.
#
# GC is disabled around each measurement block and re-enabled with a full
# sweep after, so leftover garbage from one row's setup doesn't drift into
# the next row's allocs.
#
# @param label [String] human-readable row label
# @yield invoked many times under benchmark-ips, then once under MemoryProfiler
# @return [void]
def benchmark(label, &block)
  return if BENCHMARK_CONFIG.bench && !label.downcase.include?(BENCHMARK_CONFIG.bench.downcase)

  # One untimed warm-up call so first-invocation codegen (e.g., Panko's
  # SerializationDescriptor build) doesn't bias either measurement.
  block.call

  GC.disable
  ips_report = Benchmark.ips do |x|
    x.config(time: BENCHMARK_CONFIG.ips_time, warmup: BENCHMARK_CONFIG.ips_warmup, quiet: true)
    x.report(label, &block)
  end
  GC.enable
  GC.start

  entry = ips_report.entries.first
  rate = entry.stats.central_tendency
  err = entry.stats.error_percentage

  GC.disable
  mem_report = MemoryProfiler.report(&block)
  GC.enable
  GC.start

  puts "%-58s %10s i/s ±%5.2f%%  %8d allocs  %8d retained" %
    [label, benchmark_format_rate(rate), err, mem_report.total_allocated, mem_report.total_retained]

  if BENCHMARK_CONFIG.profile == "memory"
    puts
    puts "--- memory profile: #{label} ---"
    mem_report.pretty_print(scale_bytes: true, normalize_paths: true)
    puts
  end
end

# Iterates the configured sizes for +type:+, slicing the DATASETS entry to
# each size and calling +benchmark+ per size with a label that includes the
# size suffix.
#
# @param label [String] base label; the size suffix is appended automatically
# @param type [Symbol] DATASETS registry key (e.g. +:posts+)
# @yield [records] called per size with the sliced array of Records
# @return [void]
# @raise [KeyError] when +type+ isn't registered in DATASETS
def benchmark_with_records(label, type:, &block)
  BENCHMARK_CONFIG.sizes.each do |size|
    records = DATASETS.fetch(type).first(size)
    benchmark("#{label} size=#{size}") { block.call(records) }
  end
end

# Scenario-file entry point: yields per-size records to +targets_hash_block+
# (which returns a Hash of `row_label => 0-arity callable`) and runs
# +benchmark+ per row. TARGET=<substr> filters rows at this boundary; BENCH
# filters at the +benchmark+ boundary one level down.
#
# @param label [String] scenario label, e.g. +"Simple"+
# @param type [Symbol] DATASETS registry key
# @yield [records] returns the Hash of row_label => 0-arity callable
# @return [void]
# @raise [KeyError] when +type+ isn't registered in DATASETS
def benchmark_scenario(label, type:, &targets_hash_block)
  BENCHMARK_CONFIG.sizes.each do |size|
    records = DATASETS.fetch(type).first(size)
    rows = targets_hash_block.call(records)
    rows.each do |row_label, row_callable|
      next if BENCHMARK_CONFIG.target && !row_label.downcase.include?(BENCHMARK_CONFIG.target.downcase)
      benchmark("#{label} size=#{size}/#{row_label}", &row_callable)
    end
  end
end
