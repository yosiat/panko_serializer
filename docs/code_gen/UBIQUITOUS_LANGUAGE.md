# Ubiquitous Language

The vocabulary for this codebase. Use these terms precisely; avoid the listed synonyms.

## Descriptor model (the input the library accepts)

| Term                  | Definition                                                                                                                          | Aliases to avoid                    |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| **Descriptor**        | An immutable, normalized data structure describing how to serialize one kind of record — attributes, method attributes, associations, and an optional model. | Schema, spec, definition            |
| **Field**             | The **union** of **Attribute**, **Method Attribute**, and **Association** — any **Descriptor** node that contributes one key to the output for a given **Record** (unless filtered, `if:`-skipped, or `SKIP`-ed). The three **Field kinds** differ only in how the value is sourced: direct read, **Callable** invocation, or nested **Generated Class**. Use **Field** when referring to the union; use the specific kind when the distinction matters. | property, column, entry |
| **Attribute**         | A **Field** whose value is read directly from the record via a method or hash lookup.                                               | property, column                    |
| **Method Attribute**  | A **Field** whose value is computed by invoking a callable with `(record, context)` or `(record, context, scope)`, which may return `SKIP` to omit the field. | Computed attribute, derived field   |
| **Association**       | A **Field** that links one **Descriptor** to another — expressing `:has_one` or `:has_many` between records.                        | Relation, relationship, link        |
| **Recursive Descriptor** | A **Descriptor** that references itself (directly via self-reference, or indirectly via a cycle through other **Descriptors**) through one of its **Associations**. Supported via identity-keyed caching at **Compile** and construction; one **Generated Class** per unique **Descriptor**. | Tree serializer, cyclic descriptor |
| **Kind**              | The discriminator on an Association: `:has_one` or `:has_many`.                                                                     | Type, cardinality                   |
| **Source**            | The method name to call on the record to fetch the value of an Attribute or the related records of an Association.                  | Getter, accessor                    |
| **Model**             | A single Ruby Class that records for this Descriptor are instances of, or `nil` for the generic path. When set, unlocks compile-time specialization. | Models, record class                |
| **Callable**          | Any Ruby object responding to `.call` with arity 0, 1, 2, or 3 — Proc, Lambda, or Method. Invoked positionally with `(record, context, scope)` truncated to the declared arity. Used for Method Attribute bodies and Association `if:` conditions. | Block, function, handler |

## Compilation (turning Descriptors into runnable code)

| Term                  | Definition                                                                                                           | Aliases to avoid              |
| --------------------- | -------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| **Compile**           | The pure function (operation) that takes a Descriptor, Output Mode, and Config and returns a Generated Class. Implemented by **Compiler**. | Build, generate               |
| **Compiler**          | The internal class that orchestrates **Compile**: drives the **Generator** to produce source, then materializes it into a class via `module_eval`. `Panko::CodeGen.compile` is a thin facade wrapping `Compiler.new(...).compile`. | —                             |
| **Generator**         | The internal component that walks a **Descriptor** and emits source code for the matching **Output Mode**. Invoked by **Compiler** (and by **Dump**). Domain-aware; does not eval or write files. | (none — distinct from Compiler) |
| **Code Builder**      | The internal string-accumulating helper with indentation tracking used by the **Generator**. Pure helper — no knowledge of Descriptors or Output Modes. Not ERB, not Liquid. | Template engine, renderer     |
| **Output Mode**       | `:json` (emits an Oj-driven writer path producing a String) or `:hash` (emits a path producing a Ruby Hash).         | Format, mode, output type     |
| **Generated Class**   | The Ruby class emitted for a single (Descriptor, Output Mode) pair, e.g., `PostSerializer_JSON`.                     | Compiled class, output class  |
| **Dump**              | Writing a Generated Class's source to a `.rb` file on disk. The file is runnable given a Descriptor at instantiation. | Export, serialize (the class) |
| **Generic path**      | The Record-access strategy emitted when a Descriptor's **Model** is `nil`: `_write_one` dispatches to `_write_one_hash` or `_write_one_object` via a single `is_a?(Hash)` check. Handles AR instances, POROs, and Hashes. | Tier A, fallback path |
| **Specialized path**  | The Record-access strategy emitted when a Descriptor's **Model** is set: the Generator introspects the class at Compile time and emits AR-aware access (e.g., `_read_attribute` for column-backed attributes without reader overrides). No Hash-access branch. | Tier B, fast path |

## Runtime (when the Generated Class executes)

| Term                  | Definition                                                                                                                     | Aliases to avoid                  |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------ | --------------------------------- |
| **Record**            | The thing being serialized — an ActiveRecord instance, a Hash, or (via method dispatch) any plain Ruby object.                 | Object, model instance, row, item |
| **Context**           | An arbitrary caller-supplied value threaded unmodified through every call, available to Method Attributes and Association `if:` conditions. Conventionally used for environment data (e.g., request headers). | Env, state, request context       |
| **Scope**             | An arbitrary caller-supplied value, threaded unmodified through every Callable invocation. Byte-identical to **Context** in behaviour but distinct in identity. Conventionally used for auth/viewer data (e.g., `current_user`), in contrast to **Context** which is conventionally used for environment data. | viewer, current_user, actor       |
| **Filter**            | A caller-supplied inclusion/exclusion rule applied to the descriptor tree at serialize time to prune fields or associations.   | Selector, sparse fieldset         |
| **Writer**            | An `Oj::StringWriter` instance allocated at the top of a JSON-mode serialization and threaded through composed Generated Classes. | Stream, buffer, sink             |
| **SKIP**              | The module-level frozen singleton `Panko::CodeGen::SKIP`. Returning it from a Method Attribute body causes that field to be omitted (identity-compared, never matches real data). | Omit sentinel, null-skip marker |
| **Root Key**          | An optional top-level wrapper key applied to the output (e.g., `{"post": {...}}`). Enabled at compile time via Config; the string key is supplied per-call. | Envelope, wrapper                 |
| **Config**            | The compile-time settings Data struct — `null_for_missing_has_one`, `supports_root_key`. Baked into Generated Class code; no runtime mutation. | Options, settings                 |

## Composition & integration

| Term                  | Definition                                                                                                                  | Aliases to avoid                 |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| **Composition**       | The architectural choice for nested Associations: each Descriptor compiles to its own Generated Class; parents hold nested Generated Class instances as ivars and call them. Contrast with **Inlining** (rejected). | Delegation                       |
| **Environment**       | The Descriptor passed to a dumped Generated Class at instantiation, from which callables and nested Generated Classes are resolved. | Context (overloaded — don't)     |
| **Panko**             | The host gem; `Panko::CodeGen` is its internal engine. Its public DSL emits Descriptors as its intermediate representation. | Consumer, host                   |

## Relationships

- A **Descriptor** contains zero or more **Fields**, of three kinds: **Attributes**, **Method Attributes**, and **Associations**.
- An **Association** names another **Descriptor** (and its own **Kind**, **Source**, and optional **`if`** **Callable**).
- **Compile** maps one **Descriptor** × one **Output Mode** × one **Config** to one **Generated Class**.
- Two **Generated Classes** for the same **Descriptor** (one per **Output Mode**) can coexist and are independent.
- A **Generated Class** for a parent **Descriptor** holds nested **Generated Class** instances (one per inner **Association**) as ivars — this is **Composition**.
- At runtime, **`serialize_one`** / **`serialize_many`** take a **Record** (or Records) plus **Context** and **Filter**, and in JSON mode additionally manage a **Writer**.
- **Panko** produces **Descriptors**, caches **Generated Classes**, and owns the user-facing DSL — this library does none of those.

## Example dialogue

> **Dev:** "So when Panko passes in a **Descriptor** with a `:comments` **Association** whose **Kind** is `:has_many`, you generate one **Generated Class** per **Output Mode**?"

> **Library author:** "Right. **Compile** takes the **Descriptor**, an **Output Mode**, and a **Config**, and returns one **Generated Class**. **Composition** means the parent's class holds a nested `CommentSerializer_JSON` instance as an ivar — not inlined code."

> **Dev:** "And each **Method Attribute**'s **Callable** gets invoked with `(record, context)` — what if it returns `SKIP`?"

> **Library author:** "Then the generated code does an identity-compare against **SKIP** and skips writing that key to the **Writer** (JSON) or the output hash. **Context** is passed through; the **Callable** uses it however it wants."

> **Dev:** "Does **Filter** thread through **Composition** the same way **Context** does?"

> **Library author:** "Yes — both get passed as positional args to the inner **Generated Class**'s `_write_one` method. The inner class re-scopes **Filter** to its own subtree before applying."

## Flagged ambiguities

- **"Serializer"** is overloaded. The user-facing Panko class (`class PostSerializer < Panko::Serializer`) is *not* the same thing as the **Generated Class** this library produces (`PostSerializer_JSON`). In this codebase's vocabulary, "serializer" alone should be avoided — say **Panko serializer** or **Generated Class** explicitly. The **Descriptor** is the bridge between them.
- **"Compile"** vs **"Generate"**. Use **Compile** for the top-level operation (Descriptor → Generated Class) and **Generate**/**Emit** for the internal act of producing source code lines inside the Generator. Don't use them interchangeably.
- **"Context"** has a second meaning (the descriptor-as-environment for dumped files). For that, use **Environment** exclusively to disambiguate.
- **"Attribute"** vs **"Method Attribute"** are distinct descriptor nodes with distinct compile paths — don't call either one just "attribute." Panko's current DSL calls both `attribute`, but the **Descriptor** level splits them.
- **"Field"** is the **union** of **Attribute**, **Method Attribute**, and **Association** — not a synonym for **Attribute**. When someone says "filter this field," they may mean any of the three. When you need to be specific about the source-of-value (direct read vs callable vs nested serializer), use the specific kind name. When the distinction doesn't matter (e.g., "every Field is filterable by name"), **Field** is the right word.
- **"Object"** (Panko's current ivar name for the record inside a method attribute body, e.g., `object.id * 2`) is a Panko-internal convention. At the descriptor-library boundary, the term is **Record** — passed explicitly to the **Callable**.
