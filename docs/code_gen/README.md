# Panko::CodeGen — engine design docs

Design decisions, architecture, and API surface for Panko's code-generation engine,
`Panko::CodeGen` (`lib/panko/code_gen/`).

All documents use the vocabulary defined in [`UBIQUITOUS_LANGUAGE.md`](UBIQUITOUS_LANGUAGE.md).
Read that first; every term in bold elsewhere is defined there.

## Table of contents

| Document                                          | Summary                                                                       |
| ------------------------------------------------- | ----------------------------------------------------------------------------- |
| [goals.md](goals.md)                              | Why this library exists, scope, non-goals, primary consumer                   |
| [descriptor.md](descriptor.md)                    | The **Descriptor** input shape — **Attributes**, **Method Attributes**, **Associations**, **Model**, **Callables** |
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
| [benchmarks.md](benchmarks.md)                    | Benchmark harness, scenario layout, comparison targets, baseline workflow   |
| [merging-into-panko.md](merging-into-panko.md)    | Design boundary decisions — invariants of the subsystem at the Panko seam   |
| [deferred.md](deferred.md)                        | Explicitly punted items and the version they're deferred to                  |
| [research/](research/)                            | Benchmarks and spikes that informed specific decisions                       |

## Stage

Implemented and merged. The engine lives at [`lib/panko/code_gen/`](../../lib/panko/code_gen/)
and is the only engine behind `serialize` / `serialize_to_json`. The living documents above
are kept aligned with the code; [research/](research/), [merging-into-panko.md](merging-into-panko.md),
and [deferred.md](deferred.md) are historical records of how the design got here.
