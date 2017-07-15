# frozen_string_literal: true
source "https://rubygems.org"

gemspec

version = '4.2'
gem_version = "~> #{version}.8"

gem 'rails', gem_version
gem 'railties', gem_version
gem 'activesupport', gem_version
gem 'activemodel', gem_version
gem 'actionpack', gem_version
gem 'activerecord', gem_version, group: :test

group :benchmarks do
  gem 'sqlite3'
  gem 'pg'

  gem 'memory_profiler'
  gem 'ruby-prof'
  gem 'ruby-prof-flamegraph'

  gem 'benchmark-ips'
  gem 'active_model_serializers', '0.9.7'

  gem 'terminal-table'
end

group :test do
  gem 'faker'
end
