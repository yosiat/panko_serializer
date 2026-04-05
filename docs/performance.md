---
title: Performance
layout: default
nav_order: 3
---

# Performance

## Microbenchmarks

The following benchmarks were run on Ruby 4.0.2 (YJIT enabled) with Rails 8.0:

| Benchmark | ip/s | Allocations |
| --- | --- | --- |
| Simple, 50 posts | 54,443 | 35 |
| Simple, 2300 posts | 1,434 | 35 |
| HasOne, 50 posts | 32,777 | 63 |
| HasOne, 2300 posts | 842 | 62 |

Full benchmark results are available in the [benchmark source](https://github.com/yosiat/panko_serializer/blob/master/benchmarks/panko_json.rb).

### Running locally

```bash
# Run all benchmarks
bundle exec rake benchmarks:all

# Run a specific benchmark suite
bundle exec rake benchmarks:run[panko_json]
bundle exec rake benchmarks:run[type_casts]

# Filter to a specific benchmark pattern
BENCH=HasOne ruby benchmarks/panko_json.rb

# Change the number of records
SIZE=500 ruby benchmarks/panko_json.rb

# Profile CPU or memory
PROFILE=cpu ruby benchmarks/panko_json.rb
PROFILE=memory ruby benchmarks/panko_json.rb
```

## Real-world benchmark

The following real-world benchmark was conducted against an early version of Panko, serializing 7,884 entries with 48 attributes and no associations.
The benchmark took place in an environment that simulates production and was run using `wrk` from a machine on the same cluster.

| Metric             | Before Panko | With Panko |
| ------------------ | ------------ | ---------- |
| Avg Response Time  | 4.89s        | 1.48s      |
| Max Response Time  | 5.42s        | 1.83s      |
| 99th Response Time | 5.42s        | 1.74s      |
| Total Requests     | 61           | 202        |

_Thanks to [Bringg](https://www.bringg.com) for providing the infrastructure for this benchmark._
