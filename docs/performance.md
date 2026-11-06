---
title: Performance
layout: default
nav_order: 3
---

# Performance

Panko is built for high-throughput serialization. This page reports Panko's own
numbers across a range of serializer shapes, how they scale with collection
size and output mode, and where the costs come from. The last section compares
them with Panko 0.8.5, the C extension.

All figures below come from the [`benchmarks/`](https://github.com/yosiat/panko_serializer/tree/master/benchmarks)
suite.

## How these were measured

-   **Tooling**: [`benchmark-ips`](https://github.com/evanphx/benchmark-ips) for
    throughput and [`memory_profiler`](https://github.com/SamSaffron/memory_profiler)
    for allocations, on the same block, after one warm-up call.
-   **Runtime**: Ruby 4.0.9 with YJIT enabled, ActiveRecord 8.1, Oj 3.17,
    SQLite in-memory.
-   **Machine**: Apple M4 Max.
-   **Rounds**: each figure is the median of 12 runs, each in a fresh process.
-   **Data**: records are eager-loaded (associations preloaded), so no N+1
    queries happen inside the measured block.
-   **Collection sizes**: 50 and 2,300 records.
-   **Output modes**: JSON (`serialize_to_json` / `ArraySerializer#to_json`) and
    Hash (`serialize` / `#to_a`).

Numbers are indicative of relative cost and will differ on your hardware. Run
the suite yourself to get numbers for your environment.

## Throughput

Iterations per second, where **one iteration serializes the entire
collection**. Higher is better.

| Shape | Records | `serialize_to_json` | `serialize` (Hash) |
| --- | ---: | ---: | ---: |
| Simple: 5 flat attributes | 50 | 74.4K i/s | 81.0K i/s |
| | 2,300 | 1.65K i/s | 1.81K i/s |
| Method attribute | 50 | 115.1K i/s | 116.5K i/s |
| | 2,300 | 2.50K i/s | 2.60K i/s |
| `has_one` association | 50 | 54.9K i/s | 56.3K i/s |
| | 2,300 | 1.18K i/s | 1.21K i/s |
| `has_many`: 5 children each | 50 | 20.9K i/s | 18.4K i/s |
| | 2,300 | 416 i/s | 385 i/s |
| Wide: 70 attributes | 50 | 3.93K i/s | 3.98K i/s |
| | 2,300 | 81.0 i/s | 79.3 i/s |

Throughput scales close to **linearly** with the number of records, so the
per-record cost stays roughly constant across collection sizes. For the simple
shape in JSON, that's about 3.7M records per second at 50 records and 3.8M at
2,300.

## Allocations

Objects allocated per call. Fewer is better: allocations drive garbage
collection, which is a large part of serialization cost.

| Shape | Records | `serialize_to_json` | `serialize` (Hash) |
| --- | ---: | ---: | ---: |
| Simple | 50 | 3 | 53 |
| | 2,300 | 3 | 2,303 |
| Method attribute | 50 | 3 | 53 |
| | 2,300 | 3 | 2,303 |
| `has_one` | 50 | 3 | 103 |
| | 2,300 | 3 | 4,603 |
| `has_many` | 50 | 3 | 353 |
| | 2,300 | 3 | 16,103 |
| Wide (70 attrs, 5 decimals and 5 dates) | 50 | 503 | 553 |
| | 2,300 | 23,006 | 25,303 |

Two things stand out:

-   **JSON output allocates a constant handful of objects**, no matter how
    many records: 3, whether you serialize 50 or 2,300. Panko streams values
    straight into an `Oj::StringWriter` rather than building an intermediate
    Hash, so the collection size doesn't register in allocations. This holds
    for strings, integers, booleans, method attributes, and associations.

-   **Hash output allocates one Hash per serialized object** (each record plus
    each associated record), so its allocation count grows with the
    collection. That's inherent to returning a materialized Hash. Use JSON
    output when you're producing a JSON response and don't need the Hash.

The **Wide** row is the exception. Each decimal and date is formatted into a
String, and formatting allocates: 10 objects per record for its 5 decimals and
5 dates, in both modes. Hash output adds its one Hash per record on top.

## Compared with 0.8.5

The same scenarios, run against Panko 0.8.5 (the C extension) on the same Ruby
and machine, alternating the two engines in each round. Both produced identical
output on every row before timing.

| Output | Speed vs 0.8.5 | Allocations vs 0.8.5 |
| --- | --- | --- |
| JSON, 38 rows | **1.78x** faster (0.91x to 3.29x) | **3.9x** fewer |
| Hash, 26 rows | **2.88x** faster (1.09x to 11.15x) | **1.55x** fewer |

Figures are geometric means across rows, with the slowest and fastest row in
parentheses. Two cases do not win:

-   **JSON output of a `json` or `jsonb` column** runs at parity with 0.8.5
    (1.01x to 1.04x) and allocates 3 objects per record where 0.8.5 allocated 1.
-   **JSON output of date and time values** is 0.91x of 0.8.5 for 50 records.
    Hash output of the same data is 1.09x.

## Reproducing these numbers

Each scenario is a standalone script under `benchmarks/`. The scripts need an
appraisal gemfile (for ActiveRecord and the comparison libraries), so run them
through Appraisal rather than bare `ruby`:

```
bundle exec appraisal 8.1.0 ruby benchmarks/simple.rb
bundle exec appraisal 8.1.0 ruby benchmarks/has_one.rb
bundle exec appraisal 8.1.0 ruby benchmarks/has_many.rb
bundle exec appraisal 8.1.0 ruby benchmarks/method_attribute.rb
bundle exec appraisal 8.1.0 ruby benchmarks/wide_attributes.rb
```

`8.1.0` is the appraisal name; `7.2.0` and `8.0.0` are also available. A
different Ruby or Rails version shifts the absolute figures.

Useful environment knobs:

-   `SIZE=n`: run a single collection size instead of the default 50 and 2,300.
-   `TARGET=<substr>`: run only rows whose label contains it (e.g. `TARGET=panko/`).
-   `PROFILE=memory`: print a full `memory_profiler` breakdown per row.
-   `IPS_TIME=s` / `IPS_WARMUP=s`: measured and warm-up seconds per row
    (default 5 and 2).
