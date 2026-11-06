# frozen_string_literal: true

require_relative "setup"
require_relative "datasets"

BenchmarkConfig = Data.define(:size, :bench, :target, :profile, :ips_time, :ips_warmup) do
  def sizes
    size ? [size] : BENCHMARK_SIZES
  end
end

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

if BENCHMARK_CONFIG.profile == "cpu"
  StackProf.start(mode: :cpu, raw: true, interval: 1000)
  at_exit do
    StackProf.stop
    puts
    puts "=== StackProf (cpu, interval=1000us) ==="
    StackProf::Report.new(StackProf.results).print_text(false, 25)
  end
end

def benchmark_format_rate(rate)
  if rate >= 1_000_000
    "%.2fM" % (rate / 1_000_000.0)
  elsif rate >= 1_000
    "%.2fK" % (rate / 1_000.0)
  else
    "%.2f" % rate
  end
end

# GC stays on during ips: disabling it makes the error bands much wider on rows that allocate a lot.
# GC is off only while MemoryProfiler counts allocations.
def benchmark(label, &block)
  return if BENCHMARK_CONFIG.bench && !label.downcase.include?(BENCHMARK_CONFIG.bench.downcase)

  # Untimed warm-up, so first-call compilation is not counted in either measurement.
  block.call

  ips_report = Benchmark.ips do |x|
    x.config(time: BENCHMARK_CONFIG.ips_time, warmup: BENCHMARK_CONFIG.ips_warmup, quiet: true)
    x.report(label, &block)
  end

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
