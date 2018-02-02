# frozen_string_literal: true
source "https://rubygems.org"

gemspec

raw_rails_version = ENV.fetch("RAILS_VERSION", "4,2")
rails_version = "~> #{raw_rails_version}"

gem "rails", rails_version
gem "railties", rails_version
gem "activesupport", rails_version
gem "activemodel", rails_version
gem "actionpack", rails_version
gem "activerecord", rails_version, group: :test

group :benchmarks do
  gem "sqlite3"
  gem "pg", "0.21"

  gem "memory_profiler"
  gem "ruby-prof"
  gem "ruby-prof-flamegraph"

  gem "benchmark-ips"
  gem "active_model_serializers"
  gem "fast_jsonapi" if raw_rails_version.start_with? "5"

  gem "terminal-table"
end

group :test do
  gem "faker"
end

group :development do
  gem "byebug"
end
