require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'json'
require 'terminal-table'


RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc 'Run all benchmarks'
task :benchmarks do
  headings = ['Benchmark', 'ip/s', 'allocs/retained']

  files = Dir[File.join(__dir__, 'benchmarks', 'bm_*')]
  files.each do |benchmark_file|
    output = `RAILS_ENV=production ruby #{benchmark_file}`

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
