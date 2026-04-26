# GameSerializer single-record benchmark — Ruby 4.0.2 + YJIT

Benchmark script: [`game_serializer_bench.rb`](game_serializer_bench.rb)
Raw stdout: [`game_serializer_yjit_output.txt`](game_serializer_yjit_output.txt)

Direct port of [oj_serializers' `game_serializer_benchmark.rb`](https://github.com/ElMassimo/oj_serializers/blob/main/benchmarks/game_serializer_benchmark.rb)
with `serializers_code_gen` added alongside `oj_serializers` and `panko`.
Same fixture (`Tetris` game with one nested `scores → self`, one
`best_player`, two `players`), same `time: 5, warmup: 2` IPS config, same
`Oj.dump` wrap pattern. JSON output is verified byte-identical across all
three libraries before the bench runs (parity assertion at the top of the
script — any drift aborts before the comparison).

## 1. Summary verdict

`scg/json` is the fastest JSON-emitting target by a real margin: **1.31× faster
than `oj_serializers`** (`one_as_json + Oj.dump`), and **2.49× faster than
`panko`** (`serialize_to_json`). `scg/hash` (Hash output, no JSON encode) is
the fastest path overall at 727k i/s, useful when a caller wants a Hash and
will encode it later. The classic `oj_serializers as_hash` path is the
slowest because `one_as_hash` builds the Hash and `Oj.dump` then walks it
again — double work.

## 2. Environment

|                                     |                                                                                |
| ----------------------------------- | ------------------------------------------------------------------------------ |
| Ruby                                | `ruby 4.0.2 (2026-03-17 revision d3da9fec82) +YJIT +PRISM [arm64-darwin25]`    |
| ActiveRecord                        | 8.1.3                                                                          |
| YJIT                                | on                                                                             |
| Comparison targets                  | `oj_serializers` (latest), `panko_serializer` (latest)                         |
| CPU arch                            | arm64 (Apple Silicon)                                                          |

## 3. Results

`time: 5, warmup: 2` per row, GC enabled (default), single-record per call.

| #  | Variant                            |       ips |  µs/iter | error  | × slowest |
|----|------------------------------------|----------:|---------:|-------:|----------:|
| 1  | `scg/hash` (Hash output)           | 727,553   |   1.37   | ±1.1%  |   3.90×   |
| 2  | `scg/json`                         | 511,443   |   1.96   | ±1.9%  |   2.74×   |
| 3  | `oj_serializers` (`one_as_json`)   | 389,812   |   2.57   | ±1.6%  |   2.09×   |
| 4  | `scg/hash + Oj.dump`               | 242,415   |   4.13   | ±1.0%  |   1.30×   |
| 5  | `panko` (`serialize_to_json`)      | 205,552   |   4.86   | ±1.8%  |   1.10×   |
| 6  | `oj_serializers as_hash`           | 186,717   |   5.36   | ±1.4%  |   1.00×   |

### 3.1 JSON-string-out, head-to-head

| Variant            |       ips | vs scg/json |
|--------------------|----------:|------------:|
| `scg/json`         |  511,443  |       —     |
| `oj_serializers`   |  389,812  | 1.31× slower |
| `scg/hash + Oj.dump` | 242,415 | 2.11× slower |
| `panko`            |  205,552  | 2.49× slower |
| `oj_serializers as_hash` | 186,717 | 2.74× slower |

scg's `serialize_one` writes directly to a fresh `Oj::StringWriter` and
returns its string. `oj_serializers#one_as_json` builds an `Oj::StringWriter`
internally and `Oj.dump` unwraps it; that's a similar shape but with extra
allocation and dispatch overhead. `panko#serialize_to_json` allocates a
fresh serializer instance per call (mirroring the upstream benchmark's
idiomatic usage), which adds setup cost.

### 3.2 Hash-out path

`scg/hash` returns a Ruby Hash directly without going through Oj's writer.
At 727k i/s with 9 allocations per call, it's the fastest path when the
caller is going to feed the Hash to another encoder, attach it to a
larger response object, or skip JSON entirely. Adding `Oj.dump(hash)` on
top costs ~3× — JSON encoding of the built Hash dominates that path.

## 4. Adaptations from the upstream benchmark

The upstream `game_serializer_benchmark.rb` uses unpersisted `Game.new(...)`
/ `Player.new(...)` instances and prepends a module to make
`Game#scores` return `self`. This script:

- **Uses persisted records** loaded via `insert_all + find` so AR's compiled
  attribute-method path (`_read_attribute` etc.) is fully warmed before
  measurement, mirroring what serializer code-gen sees in production.
- **Defines `Game#scores` directly on the model** instead of prepending a
  module — same observable behavior, less ceremony in a self-contained script.
- **Uses `has_one :scores` for the `oj_serializers` definition** instead of
  the upstream's `flat_one :game, serializer: ScoresSerializer`. `flat_one`
  inlines the score attrs onto the parent; `has_one` nests them under a
  `"scores": {...}` key. We use `has_one` so all three libraries produce
  byte-identical JSON (verified at script start). The upstream JSON shape
  differs between rows; ours doesn't.

## 5. GC.disable

This benchmark deliberately leaves GC **enabled**. Disabling it during the
IPS measurement window is the technique our `support/benchmark.rb` harness
uses for the collection-shape phase-1 rows, but it backfires here. With a
~2 µs iteration body and ~7–60 allocs per iter, GC.disable accumulates
millions of objects across the 5-second window, and the absolute throughput
oscillates ±35–85% as the malloc subsystem grows the heap unpredictably
mid-run. Re-running the same script with GC enabled recovers ±1–2% errors
without changing the row ordering. The rule of thumb for picking between
the two:

| Iteration body                    | Allocs/iter | GC.disable verdict                 |
|-----------------------------------|------------:|------------------------------------|
| Long (≥ 100 µs, e.g. size=2300)   |  thousands  | Disable — collection-pause noise dominates |
| Medium (~10 µs, e.g. size=50)     |   hundreds  | Either works; disable still slightly better |
| Short (≤ 5 µs, single-record)     |     ≤ 60    | **Leave enabled** — heap-growth noise dominates |

The harness should expose this as a knob (env var, or auto-detect from
`memory_profiler.total_allocated × estimated_iters`) rather than hard-coding
GC.disable for every measured block. See the conversation that produced
this note for context.
