# Panko::CodeGen — engine design docs

Design decisions, architecture, and API surface for Panko's code-generation engine,
written while it was the standalone `serializers-code-gen` gem and carried over when it
was merged into Panko as `Panko::CodeGen`.

All documents use the vocabulary defined in [`UBIQUITOUS_LANGUAGE.md`](UBIQUITOUS_LANGUAGE.md).
Read that first; every term in bold elsewhere is defined there.

**Reading pre-merge names.** Most documents predate the merge and keep its vocabulary:

- `SerializersCodeGen` is now `Panko::CodeGen`; `lib/serializers_code_gen/` is now
  [`lib/panko/code_gen/`](../../lib/panko/code_gen/).
- **Models** (plural) was singularized — a **Descriptor** carries at most one `model`
  (`nil` = generic path).
- The `models:` DSL mentioned in places was retired; specialization is now automatic —
  see [auto-specialization.md](auto-specialization.md), the one document written
  post-merge.

## Table of contents

| Document                                          | Summary                                                                       |
| ------------------------------------------------- | ----------------------------------------------------------------------------- |
| [goals.md](goals.md)                              | Why this library exists, scope, non-goals, primary consumer                   |
| [descriptor.md](descriptor.md)                    | The **Descriptor** input shape — **Attributes**, **Method Attributes**, **Associations**, **Models**, **Callables** |
| [compilation.md](compilation.md)                  | The **Compile** function, **Composition**, and **Record** access strategy    |
| [generated-class.md](generated-class.md)          | Runtime API of the **Generated Class** — public entry points, constructor   |
| [output-modes.md](output-modes.md)                | JSON vs Hash **Output Modes** — structural differences, **Writer** lifecycle |
| [config.md](config.md)                            | The **Config** struct — compile-time settings                                |
| [auto-specialization.md](auto-specialization.md)  | Panko's runtime seam — per-record-class **Specialized** variants, the variant cache, guarded dispatch |
| [filters.md](filters.md)                          | **Filter** public shape, threading through **Composition**, JSON/Hash parity |
| [errors.md](errors.md)                            | Error hierarchy — `DescriptorError`, `CompileError` + subclasses             |
| [code-generation.md](code-generation.md)          | Internal **Code Builder**, backtrace strategy, source injection              |
| [dumping.md](dumping.md)                          | **Dump** to file, **Environment** contract, console inspection               |
| [structure.md](structure.md)                      | Public API surface, gem layout, **Compiler** / **Generator** / **Code Builder** layering |
| [testing.md](testing.md)                          | Testing strategy — tiers, snapshot corpus, feature-test environment         |
| [ci.md](ci.md)                                    | CI matrix, Appraisal wiring, lint/benchmark policy, lefthook hooks          |
| [benchmarks.md](benchmarks.md)                    | Benchmark harness, scenario layout, comparison targets, baseline workflow   |
| [phase-1-bar.md](phase-1-bar.md)                  | Release-gating bar for phase 1 of the initial release — hard Panko bar + soft Oj-Serializers bar |
| [merging-into-panko.md](merging-into-panko.md)    | Decisions that only make sense in the context of the eventual Panko merge   |
| [deferred.md](deferred.md)                        | Explicitly punted items and the version they're deferred to                  |
| [research/](research/)                            | Benchmarks and spikes that informed specific decisions                       |

## Stage

Implemented and merged. The engine lives at [`lib/panko/code_gen/`](../../lib/panko/code_gen/)
and is the only engine behind `serialize` / `serialize_to_json`. The living documents above
are kept aligned with the code; [research/](research/), [phase-1-bar.md](phase-1-bar.md),
[merging-into-panko.md](merging-into-panko.md), and [deferred.md](deferred.md) are
historical records of how the design got here.
