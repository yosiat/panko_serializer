---
title: Performance
layout: default
nav_order: 3
---

# Performance

Panko is built for high-throughput serialization. This page reports Panko's own
numbers across a range of serializer shapes — it is not a comparison against
other libraries. The point is to show how Panko scales with collection size and
output mode, and where its costs come from.

All figures below are reproducible with the [`benchmarks/`](https://github.com/yosiat/panko_serializer/tree/master/benchmarks)
suite.

## How these were measured

-   **Tooling** — [`benchmark-ips`](https://github.com/evanphx/benchmark-ips) for
    throughput and [`memory_profiler`](https://github.com/SamSaffron/memory_profiler)
    for allocations, on the same block, after one warm-up call.
-   **Runtime** — Ruby 4.0.2 with YJIT enabled, ActiveRecord 8.1, SQLite
    in-memory.
-   **Machine** — Apple M4 Max.
-   **Data** — records are eager-loaded (associations preloaded), so no N+1
    queries happen inside the measured block.
-   **Collection sizes** — 50 and 2,300 records.
-   **Output modes** — JSON (`serialize_to_json` / `ArraySerializer#to_json`) and
    Hash (`serialize` / `#to_a`).

Numbers are indicative of relative cost and will differ on your hardware — run
the suite yourself to get numbers for your environment.

## Throughput

Iterations per second, where **one iteration serializes the entire
collection**. Higher is better.

| Shape | Records | `serialize_to_json` | `serialize` (Hash) |
| --- | ---: | ---: | ---: |
| Simple — 5 flat attributes | 50 | 78.4K i/s | 74.0K i/s |
| | 2,300 | 1.67K i/s | 1.57K i/s |
| Method attribute | 50 | 122.9K i/s | 115.5K i/s |
| | 2,300 | 2.59K i/s | 2.45K i/s |
| `has_one` association | 50 | 56.3K i/s | 54.0K i/s |
| | 2,300 | 1.21K i/s | 1.18K i/s |
| `has_many` — 5 children each | 50 | 21.5K i/s | 18.2K i/s |
| | 2,300 | 434 i/s | 385 i/s |
| Wide — ~70 attributes | 50 | 3.69K i/s | 3.11K i/s |
| | 2,300 | 74.6 i/s | 61.2 i/s |

Throughput scales close to **linearly** with the number of records, so the
per-record cost stays roughly constant across collection sizes. For the simple
shape, that's about 3.9M records/second at both 50 and 2,300 records.

## Allocations

Objects allocated per call. Fewer is better — allocations drive garbage
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
| Wide (~70 attrs, incl. decimals & dates) | 50 | 753 | 303 |
| | 2,300 | 34,503 | 13,803 |

Two things stand out:

-   **JSON output allocates a near-constant handful of objects**, no matter how
    many records — 3, whether you serialize 50 or 2,300. Panko streams values
    straight into an `Oj::StringWriter` rather than building an intermediate
    Hash, so the collection size barely registers in allocations. This holds for
    strings, integers, booleans, method attributes, and associations.

-   **Hash output allocates roughly one Hash per serialized object** (each record
    plus each associated record), so its allocation count grows with the
    collection. That's inherent to returning a materialized Hash — use JSON
    output when you're producing a JSON response and don't need the Hash.

The **Wide** row is the honest exception: with ~70 columns including decimals
and dates, JSON output allocates per value, because each decimal and date must
be *formatted* into a string for the JSON, and formatting allocates. (Hash mode
allocates fewer objects there because decimal columns skip the formatting and
stay `BigDecimal`; dates are still formatted to their ISO-8601 String, matching
the JSON output.)

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

`8.1.0` is the appraisal name; `7.2.0` and `8.0.0` are also available. The
numbers above were measured on Ruby 4.0.2 with YJIT — a different Ruby or Rails
version shifts the absolute figures.

Useful environment knobs:

-   `SIZE=n` — run a single collection size instead of the default 50 and 2,300.
-   `TARGET=<substr>` — run only rows whose label matches (e.g. `TARGET=panko`).
-   `PROFILE=memory` — print a full `memory_profiler` breakdown per row.
