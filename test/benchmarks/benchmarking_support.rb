require 'benchmark/ips'
require 'json'

module Benchmark
  module ActiveModelSerializers
    module TestMethods
      def request(method, path)
        response = Rack::MockRequest.new(BenchmarkApp).send(method, path)
        if response.status.in?([404, 500])
          fail "omg, #{method}, #{path}, '#{response.status}', '#{response.body}'"
        end
        response
      end
    end

    def ams(label = nil, time: 10, disable_gc: true, warmup: 3, &block)
      fail ArgumentError.new, 'block should be passed' unless block_given?

      GC.start

      if disable_gc
        GC.disable
      else
        GC.enable
      end

      report = Benchmark.ips(time, warmup, true) do |x|
        x.report(label) { yield }
      end

      entry = report.entries.first

			output = sprintf "%s\t%8d ip/s\t%8d allocs/op", label, entry.ips, count_total_allocated_objects(&block)
			puts output
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
