require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

desc "Run all benchmarks"
task :benchmarks do
  format = ENV.fetch('format', 'pretty')

  files = Dir[File.join(__dir__, 'benchmarks', 'bm_*')]

  if format == 'markdown'
    puts "| Framework  | Count   | ip/s   | objects |"
    puts "| ------     |  ------ | ------ | ------  |"
  end

  files.each do |benchmark_file|
    system("FORMAT=#{format} RAILS_ENV=production ruby #{benchmark_file}")
  end
end
