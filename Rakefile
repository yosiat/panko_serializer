# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "json"
require "terminal-table"
require "rake/extensiontask"
require "pty"
require "standard/rake"

gem = Gem::Specification.load(File.dirname(__FILE__) + "/panko_serializer.gemspec")

Rake::ExtensionTask.new("panko_serializer", gem) do |ext|
  ext.lib_dir = "lib/panko"
end

Gem::PackageTask.new(gem) do |pkg|
  pkg.need_zip = pkg.need_tar = false
end

RSpec::Core::RakeTask.new(:spec)
Rake::Task[:spec].prerequisites << :compile
Rake::Task[:compile].prerequisites << :clean

task default: :spec

def print_and_flush(str)
  print str
  $stdout.flush
end

def run_process(cmd)
  puts "> Running #{cmd}"
  lines = []
  stderr_reader, stderr_writer = IO.pipe
  PTY.spawn(cmd, err: stderr_writer.fileno) do |stdout, stdin, pid|
    stdout.each do |line|
      print_and_flush "."
      lines << line
    end
  rescue Errno::EIO
    # ignore this
  end

  lines
rescue PTY::ChildExited
  puts "The child process exited! - #{cmd}"
  []
end

def run_benchmarks(files, items_count: 2_300)
  headings = ["Benchmark", "ip/s", "allocs/retained"]
  files.each do |benchmark_file|
    lines = run_process "ITEMS_COUNT=#{items_count} RAILS_ENV=production ruby #{benchmark_file}"
    rows = lines.map do |line|
      row = JSON.parse(line)
      row.values
    rescue JSON::ParserError
      puts "> [ERROR] Failed running #{benchmark_file} - #{lines.join}"
    end

    puts "\n\n"
    title = File.basename(benchmark_file, ".rb")
    table = Terminal::Table.new title: title, headings: headings, rows: rows
    puts table
  end
end

desc "Run all benchmarks"
task :benchmarks do
  run_benchmarks Dir[File.join(__dir__, "benchmarks", "**", "bm_*")]
end

desc "Type Casts - Benchmarks"
task :bm_type_casts do
  run_benchmarks Dir[File.join(__dir__, "benchmarks", "type_casts", "bm_*")], items_count: 0
end

desc "Sanity Benchmarks"
task :sanity do
  puts Time.now.strftime("%d/%m %H:%M:%S")
  puts "=========================="

  run_benchmarks [
    File.join(__dir__, "benchmarks", "sanity.rb")
  ], items_count: 2300

  puts "\n\n"
end
