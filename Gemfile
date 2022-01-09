# frozen_string_literal: true
source "https://rubygems.org"

gemspec

raw_rails_version = ENV.fetch("RAILS_VERSION", "6.1.0")
rails_version = "~> #{raw_rails_version}"

gem "activesupport", rails_version
gem "activemodel", rails_version
gem "activerecord", rails_version, group: :test



group :benchmarks do
  gem "sqlite3", "~> 1.4"
  # Reference: https://github.com/ged/ruby-pg/issues/414
  gem "pg", "1.3.0.rc2"

  gem "memory_profiler"
  gem "ruby-prof", platforms: [:mri]
  gem "ruby-prof-flamegraph", platforms: [:mri]

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
  gem "rubocop"
end
