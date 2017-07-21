require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'json'
require 'terminal-table'
require 'rake/extensiontask'

Rake::ExtensionTask.new('panko') do |ext|
  ext.lib_dir = 'lib/panko'
end

RSpec::Core::RakeTask.new(:spec)
Rake::Task[:spec].prerequisites << :compile


task default: :spec


def run_benchmarks(files, items_count: 14_000)
  headings = ['Benchmark', 'ip/s', 'allocs/retained']
  files.each do |benchmark_file|
    output = `ITEMS_COUNT=#{items_count} RAILS_ENV=production ruby #{benchmark_file}`

    rows = output.each_line.map do |line|
      result = JSON.parse(line)
      result.values
    end

    puts "\n\n"
    title = File.basename(benchmark_file, '.rb')
    table = Terminal::Table.new title: title, headings: headings, rows: rows
    puts table
  end
end

desc 'Run all benchmarks'
task :benchmarks do
  run_benchmarks Dir[File.join(__dir__, 'benchmarks', '**', 'bm_*')]
end

desc 'Type Casts - Benchmarks'
task :bm_type_casts do
  run_benchmarks Dir[File.join(__dir__, 'benchmarks', 'type_casts', 'bm_*')]
end

desc 'Sanity Benchmarks'
task :sanity do
  puts Time.now.strftime('%d/%m %H:%M:%S')
  puts '=========================='

  run_benchmarks [
    File.join(__dir__, 'benchmarks', 'sanity.rb')
  ], items_count: 2300

  puts "\n\n"
end
