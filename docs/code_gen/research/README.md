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

## Conventions

- Every note starts with a one-paragraph **summary verdict** so a reader doesn't have
  to dig through numbers to find the conclusion.
- Benchmarks target Ruby 4.0.2 + YJIT (the production target). No-JIT numbers are
  secondary; ZJIT is not yet production-ready and not benchmarked.
- `bundle install` from this directory uses the global gem store; `Gemfile.lock`
  pins versions for reproducibility.
