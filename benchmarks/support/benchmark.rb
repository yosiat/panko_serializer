# frozen_string_literal: true

require "bundler/setup"
require "benchmark/ips"
require "memory_profiler"
require "active_support/all"

# Enable YJIT if available (Ruby 3.1+)
RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Sizes to benchmark. Override with SIZE=n env var (single run).
# @return [Array<Integer>]
BENCHMARK_SIZES = ENV["SIZE"] ? [Integer(ENV["SIZE"])] : [50, 2300]

# Registry of pre-loaded dataset slices, keyed by type symbol.
# Populated by support/datasets.rb before any benchmark file runs.
# @return [Hash{Symbol => Hash}]
DATASETS = {}

# Benchmark.ips measurement time in seconds (default 10).
# @return [Integer]
IPS_TIME = Integer(ENV.fetch("IPS_TIME", 10))

# Benchmark.ips warmup time in seconds (default 3).
# @return [Integer]
IPS_WARMUP = Integer(ENV.fetch("IPS_WARMUP", 3))

# ---------------------------------------------------------------------------
# NoopWriter
# ---------------------------------------------------------------------------

# A no-op Oj::StringWriter stand-in used by benchmarks that test
# serialization logic without paying JSON-string allocation costs.
class NoopWriter
  # The last value passed to push_value.
  # @return [Object, nil]
  attr_reader :value

  # Records +value+ without writing JSON.
  #
  # @param value [Object] the value to (not) write
  # @param key [String, nil] ignored
  # @return [void]
  def push_value(value, key = nil)
    @value = value
  end

  # No-op JSON push.
  #
  # @param value [String] ignored
  # @param key [String, nil] ignored
  # @return [nil]
  def push_json(value, key = nil) # rubocop:disable Lint/UnusedMethodArgument
    nil
  end
end

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

# @!visibility private
@header_printed = false

# @!visibility private
@profile_blocks = []

# ---------------------------------------------------------------------------
# print_header
# ---------------------------------------------------------------------------

# Prints the benchmark table header once, deriving the section title from
# the calling file's basename (without extension).
#
# @return [void]
def print_header
  return if @header_printed

  @header_printed = true

  title = File.basename($PROGRAM_NAME, ".*")
  width = 78
  puts "=" * width
  puts "  #{title}".center(width)
  puts "=" * width
  puts "benchmark                                                   ips     allocs   retained"
  puts "-" * width
end

# ---------------------------------------------------------------------------
# benchmark
# ---------------------------------------------------------------------------

# Runs a single benchmark case, printing one formatted result row.
#
# Respects the BENCH env var: if set, only runs benchmarks whose +label+
# contains the value as a case-insensitive substring.
#
# When PROFILE=cpu  : collects the block for a single StackProf run at exit.
# When PROFILE=memory: runs MemoryProfiler and calls pretty_print immediately.
# Normal mode       : disables GC, measures allocations + ips, prints a row.
#
# @param label [String] human-readable name shown in the output table
# @yield the code under measurement (called many times by Benchmark.ips)
# @return [void]
def benchmark(label, &block)
  filter = ENV["BENCH"]
  return if filter && !label.downcase.include?(filter.downcase)

  print_header

  case ENV["PROFILE"]
  when "cpu"
    @profile_blocks << [label, block]
    return
  when "memory"
    report = MemoryProfiler.report(&block)
    report.pretty_print
    return
  end

  GC.start
  GC.disable

  memory_report = MemoryProfiler.report(&block)

  ips_result = Benchmark.ips(IPS_TIME, IPS_WARMUP, true) do |x|
    x.report(label, &block)
  end

  GC.enable

  ips = ips_result.entries.first.ips.round(2)
  allocs = memory_report.total_allocated
  retained = memory_report.total_retained

  ips_str = format("%.2f", ips).reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
  allocs_str = allocs.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
  retained_str = retained.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse

  puts format("%-54s %12s %10s %10s", label, ips_str, allocs_str, retained_str)
end

# ---------------------------------------------------------------------------
# benchmark_with_records
# ---------------------------------------------------------------------------

# Iterates BENCHMARK_SIZES and runs one benchmark per size, automatically
# slicing the dataset registered under +type+.
#
# @param label [String] benchmark label prefix (size + noun are appended)
# @param type [Symbol] key into DATASETS (e.g. :posts)
# @yield [records] the subset of records for this size
# @yieldparam records [Array] first +n+ records from the dataset
# @return [void]
def benchmark_with_records(label, type:, &block)
  dataset = DATASETS.fetch(type)
  data = dataset[:data]
  noun = dataset[:noun]

  BENCHMARK_SIZES.each do |n|
    subset = data.first(n)
    benchmark("#{label}, #{n} #{noun}") { block.call(subset) }
  end
end

# ---------------------------------------------------------------------------
# run_cpu_profile
# ---------------------------------------------------------------------------

# Runs all blocks collected in PROFILE=cpu mode under a single StackProf
# session and prints the results.
#
# @return [void]
def run_cpu_profile
  return if @profile_blocks.empty?

  require "stackprof"

  combined = @profile_blocks.map { |_lbl, blk| blk }

  profile = StackProf.run(mode: :cpu, raw: true) do
    combined.each(&:call)
  end

  StackProf::Report.new(profile).print_text
end

# ---------------------------------------------------------------------------
# at_exit
# ---------------------------------------------------------------------------

at_exit do
  run_cpu_profile if ENV["PROFILE"] == "cpu"
  puts "=" * 78 if @header_printed
end
