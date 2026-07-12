# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :benchmarks do
  gem "stackprof"
  gem "pg"

  gem "benchmark-ips"
  gem "memory_profiler"

  # Comparison targets for the cross-library benchmark (panko vs competitors).
  gem "oj_serializers"
  gem "alba"
  gem "blueprinter"
end

group :test do
  gem "faker"
  gem "temping"
end

group :development do
  gem "byebug"
  gem "rake"
  gem "rspec", "~> 3.0"
  gem "lefthook"
end

group :development, :test do
  gem "rubocop"

  gem "standard"
  gem "standard-performance"
  gem "rubocop-performance"
  gem "rubocop-rspec"
end
