# Research

Data-gathering notes and benchmarks that informed design decisions in the parent docs.
Each note is self-contained; the top-level docs cite results from here.

## Notes

| File                                                                       | Informs                                                                                       |
| -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| [`ar_access_bench.rb`](ar_access_bench.rb)                                 | Runnable benchmark script. `bundle exec ruby --yjit ar_access_bench.rb` from this directory. |
| [`ar_access_yjit_output.txt`](ar_access_yjit_output.txt)                   | Raw stdout from the benchmark run.                                                            |
| [`ar_access_results.md`](ar_access_results.md)                             | AR attribute access comparison on Ruby 4 + YJIT. Picks `_read_attribute` as the emit form for column-backed attrs. |
| [`define_attribute_methods_safety.md`](define_attribute_methods_safety.md) | Safety of calling `Model.define_attribute_methods` defensively across Rails 7.2/8.0/8.1.     |
| [`phase_1_report.md`](phase_1_report.md)                                   | Phase-1 benchmark verdict — pre-registered skeleton (S12.1); numbers land in S12.2, verdict in S12.3, closeout in S12.4. Canonical baseline for filter-overhead comparisons in S13/S14. |
| [`filter_experiments_results.md`](filter_experiments_results.md)           | Phase-2 filter experiment verdict — pre-registered skeleton (S13.1); harness lands in S13.2, canonical run + verdict backfill in S13.3. Picks the winning cell from `{Hash-wrapper, Set-index} × {single-path, dual-path}` for S14 to ship. |
| [`phase_2_report.md`](phase_2_report.md)                                   | Phase-2 filter-implementation overhead — pre-registered skeleton (S14.5); canonical re-run + verdict backfill in S14.6. Verifies no-filter rows stay within 5% of `phase_1_report.md` (baseline integrity) and with-filter rows stay within ±10% of `filter_experiments_results.md § 6` (verdict-cell sanity). |
| [`game_serializer_bench.rb`](game_serializer_bench.rb)                     | Runnable port of [oj_serializers' GameSerializer benchmark](https://github.com/ElMassimo/oj_serializers/blob/main/benchmarks/game_serializer_benchmark.rb) with scg added. `bundle exec ruby --yjit game_serializer_bench.rb` from this directory. |
| [`game_serializer_yjit_output.txt`](game_serializer_yjit_output.txt)       | Raw stdout from the GameSerializer bench run.                                                |
| [`game_serializer_results.md`](game_serializer_results.md)                 | Single-record GameSerializer comparison: scg/json wins (1.31× faster than oj_serializers, 2.49× faster than panko); also documents the GC.disable iteration-time threshold. |

## Conventions

- Every note starts with a one-paragraph **summary verdict** so a reader doesn't have
  to dig through numbers to find the conclusion.
- Benchmarks target Ruby 4.0.2 + YJIT (the production target). No-JIT numbers are
  secondary; ZJIT is not yet production-ready and not benchmarked.
- `bundle install` from this directory uses the global gem store; `Gemfile.lock`
  pins versions for reproducibility.
