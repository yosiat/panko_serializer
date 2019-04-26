# frozen_string_literal: true
source "https://rubygems.org"

gemspec

raw_rails_version = ENV.fetch("RAILS_VERSION", "5.2")
rails_version = "~> #{raw_rails_version}"

gem "activesupport", rails_version
gem "activemodel", rails_version
gem "activerecord", rails_version, group: :test

group :benchmarks do
  gem "sqlite3"

  if raw_rails_version.include? "4.2"
    gem "pg", "~> 0.15"
  else
    gem "pg", ">= 0.18", "< 2.0"
  end

  gem "memory_profiler"
  gem "ruby-prof"
  gem "ruby-prof-flamegraph"

  gem "benchmark-ips"
  gem "active_model_serializers"
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
