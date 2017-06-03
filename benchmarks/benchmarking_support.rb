require 'benchmark/ips'
require 'json'
require 'terminal-table'

module Benchmark
  module ActiveModelSerializers

    def ams(label = nil, time: 10, disable_gc: true, warmup: 3, &block)
      fail ArgumentError.new, 'block should be passed' unless block_given?

      GC.start

      if disable_gc
        GC.disable
      else
        GC.enable
      end

      allocs = count_total_allocated_objects(&block)

      report = Benchmark.ips(time, warmup, true) do |x|
        x.report(label) { yield }
      end

      results = {
        label: label,
        ips: report.entries.first.ips.round(2),
        allocs: allocs
      }.to_json

      puts results

    end

    def count_total_allocated_objects
      if block_given?
        key =
          if RUBY_VERSION < '2.2'
            :total_allocated_object
          else
            :total_allocated_objects
          end

        before = GC.stat[key]
        yield
        after = GC.stat[key]
        after - before
      else
        -1
      end
    end
  end

  extend Benchmark::ActiveModelSerializers
end
