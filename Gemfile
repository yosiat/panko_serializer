# frozen_string_literal: true

source "https://rubygems.org"

gemspec

raw_rails_version = ENV.fetch("RAILS_VERSION", "7.1.0")
rails_version = "~> #{raw_rails_version}"

gem "activesupport", rails_version
gem "activemodel", rails_version
gem "activerecord", rails_version, group: :test

group :benchmarks do
  gem "sqlite3", "~> 1.4"
  gem "pg", ">= 0.18", "< 2.0"

  gem "memory_profiler"
  gem "ruby-prof", platforms: [:mri]
  gem "ruby-prof-flamegraph", platforms: [:mri]

  gem "benchmark-ips"
  gem "active_model_serializers", "~> 0.10"
  gem "terminal-table"
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
