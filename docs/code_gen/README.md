# serializers-code-gen — design docs

Design decisions, architecture, and API surface for the code-generated serializer library
that will be absorbed into [Panko](https://github.com/yosiat/panko_serializer).

All documents use the vocabulary defined in [`../UBIQUITOUS_LANGUAGE.md`](../UBIQUITOUS_LANGUAGE.md).
Read that first; every term in bold elsewhere is defined there.

## Table of contents

| Document                                          | Summary                                                                       |
| ------------------------------------------------- | ----------------------------------------------------------------------------- |
| [goals.md](goals.md)                              | Why this library exists, scope, non-goals, primary consumer                   |
| [descriptor.md](descriptor.md)                    | The **Descriptor** input shape — **Attributes**, **Method Attributes**, **Associations**, **Models**, **Callables** |
| [compilation.md](compilation.md)                  | The **Compile** function, **Composition**, and **Record** access strategy    |
| [generated-class.md](generated-class.md)          | Runtime API of the **Generated Class** — public entry points, constructor   |
| [output-modes.md](output-modes.md)                | JSON vs Hash **Output Modes** — structural differences, **Writer** lifecycle |
| [config.md](config.md)                            | The **Config** struct — compile-time settings                                |
| [code-generation.md](code-generation.md)          | Internal **Code Builder**, backtrace strategy, source injection              |
| [dumping.md](dumping.md)                          | **Dump** to file, **Environment** contract, console inspection               |
| [open-questions.md](open-questions.md)            | Design threads not yet resolved                                              |
| [deferred.md](deferred.md)                        | Explicitly punted items and the version they're deferred to                  |

## Stage

Pre-implementation. This directory captures the design reached through a grilling/design session;
no code exists yet. Intended as source material for PRDs and future refinement.
