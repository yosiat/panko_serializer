# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :benchmarks do
  gem "vernier"
  gem "stackprof"
  gem "pg"

  gem "benchmark-ips"
  gem "memory_profiler"
end

group :test do
  gem "faker"
  gem "temping"
end

group :development do
  gem "byebug"
  gem "rake"
  gem "rspec", "~> 3.0"

end

group :development, :test do
  gem "rubocop"

  gem "standard"
  gem "standard-performance"
  gem "rubocop-performance"
  gem "rubocop-rspec"
end
