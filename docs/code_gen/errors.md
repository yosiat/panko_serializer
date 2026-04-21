# Errors

All exceptions raised by this library inherit from a single root class, organized in a
shallow hierarchy by **phase** (when the error is detected) and **reason** (what went
wrong). Callers rescue the specific subclass they care about, or the root for a catch-all.

## Hierarchy

```
SerializersCodeGen::Error < StandardError
├── SerializersCodeGen::DescriptorError    # structural validation at Data.new
└── SerializersCodeGen::CompileError       # semantic validation at Compile time
    ├── NameCollisionError   # two Fields share a name at the same level
    ├── UnknownSourceError   # specialized-path Attribute Source not resolvable
    └── ArityError           # Callable arity not in {0, 1, 2}
```

**Runtime errors** (inside `_write_one` / `_to_hash`) are not wrapped. A missing method
on a **Record** raises Ruby's own `NoMethodError`; a misbehaving **Callable** raises
whatever it raises. The library does not rescue on the hot path — error wrapping would
cost per-**Field** and per-**Callable** overhead, and Ruby's native exceptions are
already self-locating via the synthetic backtrace path. See
[code-generation.md](code-generation.md) for the backtrace strategy.

## Phases

### `DescriptorError` — structural, at `Data.new`

Raised when the **Descriptor** is constructed with wrong types or shapes. Examples:

- `Descriptor#kind` is a String (should be Symbol).
- `Association#kind` is `:has_any` (not a valid enum value).
- `MethodAttribute#body` doesn't respond to `.call`.

Cheap to check; runs once per construction. Most callers see these during development,
not production.

### `CompileError` — semantic, at `Compile` time

Raised when the **Generator** walks the **Descriptor** tree and finds a problem no
structural check could catch. Runs once per **Compile** call, before any source is
emitted. The specific subclass identifies the reason:

- **`NameCollisionError`** — two **Fields** at the same level share a `name`. Since
  every **Field** contributes exactly one output key, a collision makes the output
  ambiguous.
- **`UnknownSourceError`** — the **Descriptor** sets **Models**, and an **Attribute**'s
  `source` is neither a column on every class nor an instance method on every class. See
  the 3-step classification rule in [compilation.md](compilation.md).
- **`ArityError`** — a **Callable** (Method Attribute `body` or Association `if:`) has
  an arity outside `{0, 1, 2}`. See "Callable arity" in [descriptor.md](descriptor.md).

## Message convention

Every library-raised error includes enough context to locate the offending node without a
debugger:

- The **Descriptor**'s `name`.
- The **Field** name and kind (Attribute, Method Attribute, Association).
- The specific rule violated and the observed value.

Example:

```
SerializersCodeGen::ArityError: PostDescriptor#likes_count: MethodAttribute#body has arity 3; must be 0, 1, or 2.
```

## What's not in the hierarchy

- `ArgumentError` / `TypeError` / `NoMethodError` — Ruby built-ins the library does
  *not* wrap when they originate from user code (**Callable** bodies, **Record** access).
  Catch these separately if needed.
- No `SerializersCodeGen::RuntimeError` class. If one becomes necessary (e.g., for a
  specific library-detected runtime failure not already caught by Ruby), add it under
  `Error` as a new sibling phase.
