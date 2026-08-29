# Auto-specialization

How Panko compiles and dispatches per-record-class **Specialized** variants of
a **Generated Class** — automatically, at first sight of each record class.

This document describes the caller-side runtime seam that lives in Panko
([`lib/panko/code_gen/serializer_cache.rb`](../../lib/panko/code_gen/serializer_cache.rb)),
not the engine itself. The engine stays mechanism-only — it knows how to
compile a **Descriptor** with or without a **Model**, and **Compile** is a pure
function that memoizes nothing (see [compilation.md](compilation.md)); deciding
*when* to specialize, caching the results, and dispatching per record class is
Panko's job, which is what this seam does.

## Why

The **Specialized path** ([compilation.md](compilation.md)) emits typed,
`_read_attribute`-based reads — but it needs to know the record's class at
compile time. Requiring users to declare that class in the DSL was tried and
retired (`models` DSL): the serializer usually can't know every class it will
meet, and most users would never discover the knob. Auto-specialization keeps
the generic **Generated Class** as the always-correct base and *derives* the
specialized variants at runtime, keyed by the record classes that actually
show up.

## The two tiers

Per `(serializer class, output mode)`, `SerializerCache` holds:

1. **The base** — a generic **Generated Class** plus its `InstancePool`,
   stored in class ivars on the serializer class, compiled once, read
   lock-free. This tier alone is a complete, correct engine: Hash records,
   POROs, and anything ineligible below is served by it.
2. **The variant map** — a frozen copy-on-write `Hash` of record class →
   `InstancePool`, grown at first sight of each record class. Reads never
   lock; writers replace the map wholesale (a GVL-atomic ivar swap of a
   frozen Hash) under `COMPILE_MUTEX`.

In front of both sits a **one-entry inline cache** at the serialize seams
(`Panko::Serializer` / `Panko::ArraySerializer`): a frozen `[model, pool]`
pair refreshed on every dispatch, so the common case — same record class as
last time — never touches the map at all.

## First sight of a record class

`SerializerCache.variant_pool(serializer_class, output, model)` resolves a
miss in three steps:

1. **Eligibility.** The class must pass `auto_specialize?`:
   `Panko::Config.auto_specialization.enabled`, the class responds to
   `columns_hash` and `attribute_methods_generated?` (i.e. is an AR model),
   and `DescriptorBuilder.resolvable_name?` holds — the class has a name that
   resolves back to the same class object (anonymous and unregistered classes
   fail this; the guard emit references the class by constant path).
   Ineligible classes get the base pool, **without** a map entry.
2. **Capacity.** Specialized variants per `(serializer class, mode)` are
   bounded by `Panko::Config.auto_specialization.capacity` (default 16).
   Overflow gets the base pool, no map entry, and a once-per-serializer-class
   warning. The pre-compile check is lock-free; admission re-checks under the
   mutex.
3. **Compile.** `DescriptorBuilder.specialize` rebuilds the descriptor tree
   with the model: the root gets `model`, and each association's reflected AR
   class fills its child's **Model** recursively (cycle-safe), so nested
   serializers get typed emits too. The variant compiles with
   `Config.new(guarded_model: true)` ([config.md § guarded_model](config.md))
   and gets its own `InstancePool`.

The compile runs *outside* `COMPILE_MUTEX` (mirroring the
convert-outside-the-lock discipline of `fetch`, and avoiding re-entrant
locking through `instance_pool`); a concurrent first sight may compile the
same variant twice, and the insert under the mutex keeps exactly one.

## What the map may contain

The map only ever grows with **admitted** entries:

- **Specialized variants** — bounded by `capacity`.
- **`CompileError` pins to the base pool** — a deterministic compile failure
  is stored so the failing descriptor isn't recompiled on every inline-cache
  miss. Bounded by the number of real AR classes.

Everything else — ineligible classes, capacity overflow, and
non-deterministic `StandardError` from AR introspection (connection loss,
schema not yet loaded) — returns the base pool **without inserting**.
Transient errors are left unstored deliberately, so they retry naturally on a
later miss; and per-call-minted classes can never grow the map or be pinned
against GC. The invariant: auto-specialization must never turn a serializer
that works generically into a raise — every failure mode degrades to the base.

## The guard

A variant compiled with `guarded_model: true` prepends
`record.instance_of?(<Model>)` to `_write_one` / `_to_hash`; a mismatched
record delegates to an inline generic twin body (`_generic_write_one` /
`_generic_to_hash` — same fields, duck dispatch, Hash branch). A variant
compiled for one record class can therefore never emit wrong output for
another, which is what makes heterogeneous collections safe: each record
dispatches through the seam's cache, and even a stale inline-cache hit is
caught by the guard.

`instance_of?` (not `is_a?`) is deliberate: an STI subclass may have its own
columns, overrides, and reflections, so it earns its own variant rather than
inheriting its parent's.

## Semantics and limitations

- **Verdicts freeze at first sight.** A variant's column-vs-override
  classifications are decided when the record class is first seen. A reader
  override added to a live model class afterwards is not picked up until the
  class object is replaced. A Rails/Zeitwerk reload mints new class objects —
  serializer *and* model — so development-mode edits self-heal; manually
  reopening a live class after its first serialize is unsupported
  ([descriptor.md](descriptor.md) documents the same limitation for
  serializers).
- **Reader overrides are honored.** A column whose reader is not defined by
  the model's own `GeneratedAttributeMethods` module (a user override — or
  AR's `PrimaryKey#id`) is read through the method, not `_read_attribute`.
  Measured cost of the `id` case: ~2.6ns per read under YJIT, ±0 under ZJIT —
  kept for correctness (custom primary keys, user overrides).
- **Config is read at first sight.** `enabled` / `capacity` changes after a
  variant exists don't recompile or discard it. User-facing documentation:
  [docs/configuration.md](../configuration.md).
