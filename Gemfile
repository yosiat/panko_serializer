# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :benchmarks do
  gem "vernier"
  gem "stackprof"
  gem "pg"

  gem "benchmark-ips"
  gem "active_model_serializers", "~> 0.10"
  gem "terminal-table"
  gem "memory_profiler"
end

group :test do
  gem "faker"
  gem "temping"
  gem "sqlite3"
end

group :development do
  gem "byebug"
  gem "rake"
  gem "rspec", "~> 3.0"
  gem "rake-compiler"
end

group :development, :test do
  gem "rubocop"

  gem "standard"
  gem "standard-performance"
  gem "rubocop-performance"
  gem "rubocop-rspec"
end
