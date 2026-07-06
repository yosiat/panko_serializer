# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "rake/extensiontask"

gem = Gem::Specification.load(File.dirname(__FILE__) + "/panko_serializer.gemspec")

Rake::ExtensionTask.new("panko_serializer", gem) do |ext|
  ext.lib_dir = "lib/panko"
end

Gem::PackageTask.new(gem) do |pkg|
  pkg.need_zip = pkg.need_tar = false
end

# Panko's own specs run against the compiled C extension.
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "spec/{features,unit}/**/*_spec.rb"
end
Rake::Task[:spec].prerequisites << :compile
Rake::Task[:compile].prerequisites << :clean

# The Panko::CodeGen engine specs are a separate suite with their own
# spec_helper (spec/code_gen/spec_helper.rb, loaded explicitly so a bare
# `require "spec_helper"` doesn't resolve to Panko's). They don't need the C ext.
RSpec::Core::RakeTask.new(:spec_code_gen) do |t|
  t.pattern = "spec/code_gen/**/*_spec.rb"
  t.rspec_opts = "--require ./spec/code_gen/spec_helper"
end

task default: [:spec, :spec_code_gen]

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
