# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

# Panko's own specs, run against the pure-Ruby Panko::CodeGen engine.
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "spec/{features,unit}/**/*_spec.rb"
end

# The Panko::CodeGen engine specs are a separate suite with their own
# spec_helper (spec/code_gen/spec_helper.rb, loaded explicitly so a bare
# `require "spec_helper"` doesn't resolve to Panko's).
RSpec::Core::RakeTask.new(:spec_code_gen) do |t|
  t.pattern = "spec/code_gen/**/*_spec.rb"
  t.rspec_opts = "--require ./spec/code_gen/spec_helper"
end

task default: [:spec, :spec_code_gen]

RuboCop::RakeTask.new

namespace :benchmarks do
  desc "Run all benchmarks"
  task :all do
    files = Dir["benchmarks/*.rb"].sort
    files.each { |f| system("bundle", "exec", "ruby", f) || abort("FAILED: #{f}") }
  end

  desc "Run benchmarks matching NAME (e.g., rake benchmarks:run[simple])"
  task :run, [:name] do |_, args|
    files = Dir["benchmarks/#{args[:name]}.rb"].sort
    abort "No benchmark files matching '#{args[:name]}'" if files.empty?
    files.each { |f| system("bundle", "exec", "ruby", f) || abort("FAILED: #{f}") }
  end
end
