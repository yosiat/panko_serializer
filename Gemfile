# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :benchmarks do
  gem "pg", ">= 0.18", "< 2.0"

  gem "benchmark-ips"
  gem "active_model_serializers", "~> 0.10"
  gem "terminal-table"
  gem "memory_profiler"
end

group :test do
  gem "faker"
end

group :development do
  gem "byebug"
  gem "rake"
  gem "rspec", "~> 3.0"
  gem "rake-compiler"
end

gem "standard", group: [:development, :test]
