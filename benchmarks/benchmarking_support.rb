# frozen_string_literal: true

require "benchmark/ips"
require "json"
require "memory_profiler"

module Benchmark
  module Runner
    def data
      posts = Post.all.includes(:author).to_a
      posts_50 = posts.first(50).to_a
      {all: posts, small: posts_50}
    end

    def run(label = nil, time: 10, disable_gc: true, warmup: 3, &block)
      fail ArgumentError.new, "block should be passed" unless block

      GC.start

      if disable_gc
        GC.disable
      else
        GC.enable
      end

      memory_report = MemoryProfiler.report(&block)

      report = Benchmark.ips(time, warmup, true) do |x|
        x.report(label) { yield }
      end

      results = {
        label: label,
        ips: ActiveSupport::NumberHelper.number_to_delimited(report.entries.first.ips.round(2)),
        allocs: "#{memory_report.total_allocated}/#{memory_report.total_retained}"
      }.to_json

      puts results
    end
  end

  extend Benchmark::Runner
end
