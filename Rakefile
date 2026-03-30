# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

RuboCop::RakeTask.new

namespace :benchmarks do
  desc "Run all benchmarks"
  task :all do
    files = Dir["benchmarks/*.rb", "benchmarks/type_casts/*.rb"].sort
    files.each { |f| system("bundle", "exec", "ruby", f) || abort("FAILED: #{f}") }
  end

  desc "Run benchmarks matching NAME (e.g., rake benchmarks:run[type_casts:postgresql])"
  task :run, [:name] do |_, args|
    path = args[:name].tr(":", "/")
    files = Dir["benchmarks/#{path}.rb", "benchmarks/#{path}/*.rb"].sort
    abort "No benchmark files matching '#{args[:name]}'" if files.empty?
    files.each { |f| system("bundle", "exec", "ruby", f) || abort("FAILED: #{f}") }
  end
end
