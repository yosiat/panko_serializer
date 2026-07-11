# Merging into Panko

This library is designed to be absorbed into
[Panko](https://github.com/yosiat/panko_serializer). Once the merge lands, Panko is
the only caller — there is no separate gem, no public API for non-Panko consumers,
and decisions that previously preserved a "library / caller" boundary collapse into
single Panko-internal choices.

The document has two purposes:

1. **The merge plan** (§ Merge plan below) — phases, checkpoints, and the
   mechanics that get scg into Panko cleanly while preserving commit history.
2. **Boundary decisions** (§ Boundary decisions below) — the small set of
   things scg deliberately *doesn't* own because Panko owns them on the other
   side of the boundary. These survive the merge as long-term invariants of
   the `Panko::CodeGen` subsystem.

User-visible behaviour, surface, and packaging changes that this merge
introduces — feeding the eventual migration guide and CHANGELOG — are tracked
separately in
[merging-into-panko-changes.md](merging-into-panko-changes.md). Decisions
recorded in this document promote into that one when they affect Panko users.

---

## Merge plan

### Source of truth and approach

- **Base**: `panko_serializer` master (`552ee5c` at time of writing).
- **Outcome**: scg replaces the C extension entirely. Panko's runtime engine is
  pure Ruby code-gen.
- **Public API**: 100% preserved. `Panko::Serializer` / `Panko::ArraySerializer`
  user-facing DSL unchanged.
- **Internal API**: scg becomes `Panko::CodeGen` — the engine behind every
  `serialize` / `to_json` call. Considered internal; not part of Panko's public
  surface today.
- **Specialized-model passthrough** (a Panko feature absent on master): explicitly
  out of scope for the merge. It will be re-added inside Panko after the merge
  ships.
- **Discarded alternative bases**:
  - `ruby-impl-perf` (PR [#218](https://github.com/yosiat/panko_serializer/pull/218))
    — pure-Ruby rewrite. Not chosen because we want the cleaner master starting
    point and a single rewrite step (delete C, install codegen).
  - `ruby-impl-perf-codegen` (PR [#226](https://github.com/yosiat/panko_serializer/pull/226))
    — code-gen attempt on top of `ruby-impl-perf`. Owner-judged "less best
    option, bad implementation"; abandoned in favour of scg's design.

### How history lands in Panko

Goal: every commit on scg's main lands in Panko with its **author**, **author
date**, **commit date**, and **final paths** preserved, so `git blame` walks
across the merge boundary without a rename cliff.

**Mechanic — option B from the grilling session:**

1. **On scg's main, before any rewrite**: ship one commit that renames
   `SerializersCodeGen` → `Panko::CodeGen` (module rename + filename rename
   `lib/serializers_code_gen.rb` → `lib/panko/code_gen.rb`, regen all snapshot
   fixtures, all tests pass). This is the last commit on scg's main before the
   merge; it stands on its own.
2. **In a throwaway clone of scg** (`git clone --no-local`): rewrite paths with
   `git filter-repo --path-rename`:
   ```bash
   git filter-repo \
     --path-rename lib/serializers_code_gen/:lib/panko/code_gen/ \
     --path-rename lib/serializers_code_gen.rb:lib/panko/code_gen.rb \
     --path-rename spec/:spec/code_gen/
   ```
   Order matters — directory rule before file rule so the longer prefix wins
   inside it.
3. **In Panko, on a branch off master**: `git remote add scg ../scg-rewrite`,
   `git fetch scg`, `git merge --allow-unrelated-histories scg/main`. All scg
   commits become Panko ancestors with original SHAs (post-rename) and dates.
4. **Verification (the strongest gate)**: blob SHAs at HEAD between the
   rewritten clone and a fresh untouched scg clone must be byte-identical
   (only paths moved, content unchanged). Plus:
   ```bash
   git rev-list --count HEAD                    # commit count preserved
   git log --all -- lib/serializers_code_gen/   # must be empty
   git log --follow lib/panko/code_gen/compiler.rb  # walks back across rename
   git blame lib/panko/code_gen/compiler.rb     # resolves to original commits
   ```

**Why this and not alternatives:**

- `git subtree add` without filter-repo would land scg files under the *old*
  `lib/serializers_code_gen/` paths and need a follow-up rename commit — that
  rename creates a `git blame` cliff.
- `git format-patch` + `git am` linearizes history (loses scg's review/feedback
  merge commits) and changes SHAs.
- `git subtree add --squash` discards 206 commits of slice provenance.
- BFG can't express directory renames. `josh` is overkill for a one-shot.
  `filter-branch` is deprecated by `git-scm.com` itself.

The "rumours" about filter-repo unreliability trace to *misuse* (running on
non-fresh clones, confusing `--path` filtering with `--path-rename`,
expecting GPG-signature preservation) — not data corruption. scg has no
signed commits; we'll use `--no-local` for the throwaway clone; we're using
`--path-rename` (rewrite-in-place), not `--path` (filter-include).

### Side-by-side validation strategy

Phase 1 lands scg's specs at `spec/code_gen/` in Panko, but **does not wire
them into Panko's runtime yet**. After the merge commit:

- Panko's existing specs (`spec/features/*`, `spec/unit/*`) still run against
  the C extension and pass.
- scg's specs (`spec/code_gen/**/*`) run independently and pass.
- Both CI lanes green = the merge itself is clean before any integration
  begins.

Only Phase 2 starts wiring Panko's DSL into `Panko::CodeGen`.

### Phase plan and checkpoints

Five phases. **Each numbered slice is its own commit with its own test gate.**
Frequent checkpointing means: don't let a phase accumulate uncommitted state
across multiple slices. If a slice's test gate fails, the slice is the unit of
diagnosis, not the phase.

#### Phase 0 — Prep

| Slice | Description | Gate |
|---|---|---|
| 0.1 | Draft this plan (`docs/merging-into-panko.md`) and grill it to convergence | Plan reviewed and locked |
| 0.2 | scg-side: tag a `pre-merge-baseline` on scg's current main (recoverable starting point) | Tag pushed |
| 0.3 | scg-side: prepare `Panko::CodeGen` rename commit (module rename, filename rename, snapshot regen, all specs green) | scg's full suite green |
| 0.4 | Throwaway clone: filter-repo rewrites paths; verification gate (blob SHA equality) | Verification script passes |

End-of-phase gate: rewritten scg clone is ready to merge into Panko, all
verification commands clean, plan locked.

#### Phase 1 — Land scg under `Panko::CodeGen`

| Slice | Description | Gate |
|---|---|---|
| 1.1 | In Panko: create `merge-scg` branch off master | Branch exists |
| 1.2 | `git merge --allow-unrelated-histories scg/main` | Merge commit lands; both subsystems present |
| 1.3 | Add `lefthook.yml` to Panko (mirroring scg's: `standardrb --fix` + `bundle exec rspec` on pre-commit; **no pre-push hook**) | `bundle exec lefthook install` works |
| 1.4 | Add Panko's `CLAUDE.md` (fresh content reflecting merged-but-not-yet-integrated state — not a copy of scg's) | Doc reviewed |
| 1.5 | Run Panko's existing spec suite: must still pass against C ext | `bundle exec rspec` green |
| 1.6 | Run scg's spec suite at `spec/code_gen/`: must still pass | `bundle exec rspec spec/code_gen` green |
| 1.7 | Add Appraisal/CI matrix updates so both spec lanes run in CI | CI run green |

End-of-phase gate: both subsystems coexist in one repo. C ext is still active
and is still the engine. No integration yet.

#### Phase 2 — Replace C ext with codegen (shallow seam)

Strategy **2a — delete-first, no fallback flag**. The C extension stays only
until 2.6, when it's deleted in one commit. There is no `PANKO_ENGINE=` toggle.

| Slice | Description | Gate |
|---|---|---|
| 2.1 | Audit Panko's feature-spec coverage of **codegen-relevant** behaviours (hash key types, has_one/has_many nesting, nil handling, alias mapping, method-field dispatch). **Out of scope:** type-cast / datetime / decimal formatting equivalence — see § AR scope below. Rewrite any spec that does string-equality on JSON output to parse-and-compare instead (ordering is not contract). | New specs all pass against C ext |
| 2.2 | `Panko::CodeGen::DescriptorBuilder.from_panko_descriptor(panko_desc, filters:)` — pure converter, not yet wired into runtime | Builder unit specs green |
| 2.3 | Panko-side compile cache identified by `(serializer class, output mode, models-permutation)` — a per-class Hash keyed by model class (generic + specialized); filter-agnostic (Q8.d); Config fixed at compile time (Q9) | Cache unit specs green |
| 2.4 | Replace the body of `Panko.serialize_objects` (currently the C entry point) with a Ruby method that uses DescriptorBuilder + cache + Generated Class. C ext still loaded but call site no longer hits it. | All Panko feature specs green via codegen path |
| 2.5 | Run Panko's full feature suite. Any failure = fix forward in Ruby. | Full suite green |
| 2.6 | Delete `ext/`, drop `extconf.rb`, remove the C-extension `require` from `lib/panko_serializer.rb`, update gemspec (no `spec.extensions`), drop `spec/unit/type_cast_spec.rb` (and any C-only unit specs) — **with explicit user verification before each test deletion**. | Gem builds without C extension; full suite green |

End-of-phase gate: C extension gone. Codegen is the only engine. Two
descriptor types still coexist (`Panko::SerializationDescriptor` for class-time
DSL accumulation; `Panko::CodeGen::Descriptor` produced by the converter on
each compile).

#### Phase 3 — Collapse `Panko::SerializationDescriptor` (deep seam)

Note: `Panko::SerializationDescriptor` is **not** public API today, so this
phase has no compatibility constraint. (It may become public in the future, but
post-merge.)

Slices to be detailed once Phase 2 is locked. Skeleton:

| Slice | Description | Gate |
|---|---|---|
| 3.1 | Replace `Panko::Serializer.inherited`'s `_descriptor` with a builder that produces `Panko::CodeGen::Descriptor` directly | Class-time DSL builds the immutable descriptor; specs green |
| 3.2 | Eliminate `apply_filters` mutation; filters are cache-key-only at compile time | Filtered serialization specs green |
| 3.3 | Implement `parent_class` method-field dispatch — Generated Class inherits from `Descriptor#parent_class`, `MethodAttribute#body` accepts a Symbol when `parent_class:` is set, emitter branches Symbol vs Callable. See [§ Boundary decisions — Generated Class subclasses the user's Panko serializer](#generated-class-subclasses-the-users-panko-serializer). | Method-field specs green; **self-recursion regression spec** (`CommentSerializer ↔ replies`) added and green; pre-merge benchmark vs Panko C ext recorded |
| 3.4 | Translate `has_one` / `has_many` to `Panko::CodeGen::Association` | Association specs green |
| 3.5 | Delete `lib/panko/serialization_descriptor.rb`; update every spec that pokes at `_descriptor.attributes` etc. | Suite green; one descriptor type in repo |

End-of-phase gate: single descriptor type. `Panko::SerializationDescriptor`
deleted. All Panko + scg specs green via codegen.

#### Phase 4 — Hardening

| Slice | Description | Gate |
|---|---|---|
| 4.1 | Default `Config#pool_writer` to `true` in Panko's wiring (matches scg default) | Pool-on benchmarks measured |
| 4.2 | Re-bootstrap sandcastle inside Panko (clean reboot — not a copy of scg's `.sandcastle/`) | Sandcastle run green |
| 4.3 | Benchmark parity: scg's benches added alongside Panko's existing benches under `benchmarks/`. **Dedup deferred** (per user direction). | Numbers recorded; no regression vs pre-merge baseline |
| 4.4 | Version bump and `CHANGELOG` entry | Tag created (push to remote stays a manual user step) |

End-of-phase gate: shipped state. Tagged release ready to publish.

### AR scope

**Generic path only.** scg has two emit paths for `_write_one`:

- **Specialized** — used when `Descriptor.models` is set; emits
  `record._read_attribute("name")`; monomorphic; bypasses user reader
  overrides. This is where scg's measured 1.58×–1.67× perf wins live.
- **Generic** — used when `Descriptor.models` is `nil`; emits
  `record.is_a?(Hash) ? record["name"] : record.name`; works for any
  record shape; slower per-record by one branch + method dispatch.

**Decision:** Panko's DSL never sets `models:`, so the merged engine runs
on Generic only. The Specialized path stays in the scg codebase (it's
exercised by scg's own specs and benchmarks) but is **not reachable from
Panko's DSL** in the merged gem. Adding a `models:` DSL is **not on this
plan** — it's an unscoped future Panko feature, not a follow-up of the
merge.

**Implication:** the post-merge engine likely runs slower on AR-heavy
workloads than the current C-extension Panko. **This is accepted.** The
merge is a correctness milestone, not a performance milestone.

### Type-cast scope

**Out of scope.** Panko's C extension carries ~565 LOC of bespoke
type-casting (`ext/panko_serializer/attributes_writer/type_cast/`,
including custom datetime formatting via `bytesplice`). After C-ext
deletion, AR's own Ruby type-cast pipeline becomes the only path —
codegen calls AR's column readers (or `_read_attribute`), which already
return type-cast values.

This means:

- **No type-cast characterization tests.** Phase 2.1 does not pin
  Panko's current datetime/decimal/etc. output strings. scg's existing
  spec coverage of AR type-casting is sufficient — no Panko-side
  equivalent specs needed.
- **`spec/unit/type_cast_spec.rb` is pre-approved for deletion** in 2.6
  (it's testing the C extension directly).
- **Panko tests that pin C-ext-specific datetime/time output strings**
  (e.g., a datetime formatted via `bytesplice` rather than AR's default
  `to_s(:iso8601)`) are **not deleted** in 2.5 — they are **pended**
  with a `pending: "Deferred — see merging-into-panko.md § Deferred"`
  marker. The user has flagged time-format change as a potential
  breaking change for downstream Panko consumers and will handle it
  post-merge (see § Deferred to post-merge).

### JSON column scope

scg's existing `Generators::FieldEmitters::Attribute.emit_json_column`
handles Postgres `jsonb` columns (uses `Oj.sc_parse` with a no-op
parser to validate wire format without re-parsing). Panko's feature
specs do not exercise jsonb explicitly. **No new Panko JSON-column
specs.** scg's coverage is the bar.

### Converter footguns (Phase 2.2)

Translation traps the `Panko::CodeGen::DescriptorBuilder` must get
right. None require scg-side code change — they're shape-mapping
gotchas between the two descriptor vocabularies, called out so
2.2's unit specs cover them.

#### `has_one` / `has_many` `name:` reverses meaning

Panko and scg disagree on what `name:` means on an association.

- **Panko** (`lib/panko/serializer.rb:76-106`,
  `lib/panko/association.rb`): `has_one :owner, name: :user,
  serializer: UserSerializer`. The first positional (`:owner`) is
  the **reader** — Panko calls `record.owner` to load the nested
  record, and it doubles as the default output key. The
  `name:` option (`:user`) overrides the **output key only**;
  the reader is unaffected. The `Panko::Association` constructor
  stores the first positional in `name_sym` (used for the reader)
  and `options.fetch(:name, name).to_s` in `name_str` (used as
  the output JSON key).
- **scg**
  (`lib/serializers_code_gen/generators/field_emitters/association.rb`):
  `Association(name: :user, source: :owner, ...)` splits the
  axes explicitly. `name:` is the output key; `source:` is the
  reader.

**Mapping the converter must emit:**

| Panko side | scg side |
|---|---|
| First positional (`name` arg) | `source:` |
| `options.fetch(:name, name)` | `name:` |

**Footgun.** Someone reading Panko's `has_one(name, options = {})`
signature will reasonably name the first positional `name`, see
`options[:name]`, and emit `Association(name: <first_positional>,
source: <options[:name]>)`. That's the inverse mapping —
output key swaps with reader. Phase 2.2 unit specs must include
the with-`name:` case (i.e., a `has_one` where the first
positional and `options[:name]` differ); the without-`name:` case
will pass either way because both axes collapse to the same
symbol.

#### Column-attribute aliases translate directly

Panko's class-time `aliases({created_at: :createdAt})` (rename
of the **output** key) maps directly to scg's
`Attribute(name: :createdAt, source: :created_at)`. No new
descriptor shape needed; this is the same `name:`/`source:` split
that already supports scg's existing fixtures. Already noted in
[Q7 cascade](merging-into-panko-open-questions.md#q7-method-field-translation--panko-instance-methods--scg-method-fields);
called out here for converter visibility.

### What's preserved vs dropped from scg

| Preserved | Dropped |
|---|---|
| All 206 commits (with original authorship + dates) | `.sandcastle/` directory and harness — re-bootstrapped fresh in Phase 4 |
| `docs/` (lands in Panko under `docs/code_gen/`) | (no other deletions planned at the doc level) |
| All scg specs at `spec/code_gen/` | `spec/unit/type_cast_spec.rb` (Panko-side, C-ext-only — no longer relevant) |
| All scg benchmarks (added alongside Panko's; dedup deferred) | C extension (`ext/panko_serializer/`) — deleted in 2.6 |

**Test deletion rule (hard gate):** no spec is deleted without explicit
user verification. Type-cast tests are pre-approved. Anything else triggers
a question before the delete.

### Deferred to post-merge

These items are **explicitly out of scope** for the merge. They are
known follow-ups, not open questions — each is tracked here so the
merge plan stays scoped.

- **Time / datetime output format change.** The C extension formats
  datetime values via custom `bytesplice`-based `strftime` paths
  (`ext/panko_serializer/attributes_writer/type_cast/time_conversion.c`).
  After C-ext deletion, codegen relies on AR's Ruby type-cast
  pipeline, which produces datetime strings in AR's default format
  (typically ISO 8601). **The output format may change in
  user-visible ways.** This is a potential breaking change for
  downstream Panko consumers. Handled post-merge: the user will
  decide whether to (a) accept the new format and ship a major-version
  bump notifying users, (b) restore the old format inside `Panko::CodeGen`
  via a Config knob, or (c) leave the new format as the contract and
  document the migration. Until that decision lands, tests that pin
  the old format are pended (see § Type-cast scope).

- **Specialized path with a `models:` DSL.** Adding Panko-side DSL
  syntax that lets a user declare the AR class for a serializer
  (`models Post`), routing scg to the Specialized emit path with
  `record._read_attribute("name")` access. This restores the
  1.58×–1.67× perf headroom scg has on AR-typed workloads. Unscoped;
  not on this plan.

- **`Panko::ObjectWriter` removal.** Unused after Phase 2.6 (C-ext
  deletion); can be removed in a follow-up. Tracked as a Panko-internal
  cleanup, not part of the merge.

- **Promoting `Panko::CodeGen` (or `Panko::CodeGen::Descriptor`) to
  public API.** The merge keeps the codegen subsystem internal. If
  Panko users later want to construct descriptors directly without
  going through `Panko::Serializer`, that's a future Panko design
  decision.

### Open questions

Working surface lives in
[merging-into-panko-open-questions.md](merging-into-panko-open-questions.md).
Each question is unresolved as of the last grilling session; resolutions
get promoted into this main plan as they're locked.

Currently open: **none.** **Q11 (versioning)** is deferred to release time
(analysis parked in the open-questions doc). All other questions resolved
and promoted (below / into changes.md): **Q7** (method-field translation),
**Q8** (filter mapping), **Q9** (compile-cache lifecycle), **Q10** (Ruby
version floor → `>= 3.4`), **Q12** (CI matrix → collapse onto Panko's).

The output-mode mapping question is **resolved** — see slice 2.1, § AR
scope, § Type-cast scope, and § Deferred to post-merge above.

---

## Boundary decisions

Decisions that only make sense in the context of the merge — i.e., things
we deliberately *don't* build into the library because Panko owns them on
the other side of the boundary. These survive the merge as long-term
invariants of the `Panko::CodeGen` subsystem.

### Both `scope` and `context` survive Panko's public DSL

**Decision (2026-05-09)**: Panko's public API preserves **both** `scope:` and
`context:` kwargs on `Panko::Serializer.new` and the `#scope` / `#context`
instance methods on user serializer subclasses. No deprecation, no rename, no
warning. User code that does
`def greeting; "#{context[:env]} #{scope.email}"; end` keeps working
byte-compatibly post-merge.

**Why**: dropping `scope` would force every existing Panko user to migrate —
rewrite every user method body that reads `scope`, plus every callsite that
passes `scope:` to a serializer constructor. The merge is meant to be a
near-invisible engine swap; an API break here is unrelated overhead users
shouldn't pay. **Reverses the earlier "drop scope" intent** captured in
[merging-into-panko-open-questions.md § Pause state (2026-05-09)](merging-into-panko-open-questions.md);
that direction was abandoned the same day in favour of the no-API-break
release strategy.

**Consequence inside scg**: scg promotes **both** Context and Scope to
first-class UL terms — sibling pass-through axes, byte-identical in behaviour
but distinct in identity. The Callable contract widens from `(record, context)`
to `(record, context, scope)`; `serialize_one` / `serialize_many` gain a
`scope:` kwarg alongside `context:`. **No `Panko::SerializationContext`
wrapper, no Hash bundle** — two scg-native primitives, threaded through
emitted code with no library-side semantics. The two-axis promotion is tracked
in [deferred.md § Pre-Panko-merge](deferred.md#pre-panko-merge).

- Panko's public surface — `Foo.new(context:, scope:)`, `#context`, `#scope` —
  unchanged.
- scg's runtime — receives `context: <ctx>, scope: <scope>` and threads each
  unmodified through every Callable invocation per the widened Callable
  contract.
- The Panko-side dispatcher (Q7's chosen shape) installs `@context` and
  `@scope` ivars on the receiver per call (alongside `@object`); user method
  bodies reach `context` / `scope` via simple `attr_reader`-shaped accessors
  on `Panko::Serializer`. **`Panko::SerializationContext` is deleted as part
  of the merge** — there's no wrapper class; the two values flow as separate
  scg primitives.

**Consequence on scg's UL**: gains the `Scope` term, defined as a sibling of
`Context` — "arbitrary caller-supplied value, threaded unmodified through every
Callable invocation, byte-identical to Context in behaviour but distinct in
identity." Context's definition unchanged.

### Generated Class subclasses the user's Panko serializer

**Decision (2026-05-09 PM)**: when a `Panko::CodeGen::Descriptor` carries a
`parent_class:` (set by `Panko::CodeGen::DescriptorBuilder` from any user
`Panko::Serializer` subclass), `Panko::CodeGen.compile` emits a Generated
Class that **inherits from `parent_class`** rather than from `Object`.
Method fields invoke user `def`-d methods via direct method dispatch on
`self`:

The decision-tree comparison below labels this shape **K1** (alongside
rejected alternatives **J** and **A**); throughout the rest of this doc
and the codegen subsystem we refer to it as **`parent_class` dispatch**
— the trigger field on the Descriptor names the mechanism.

```ruby
# Emitted Generated Class shape (post-merge):
Class.new(FooSerializer) do
  def _write_one(record, writer, context, scope, filters)
    @object  = record
    @context = context
    @scope   = scope
    writer.push_object
    writer.push_value(@object.name, "name")
    val = greeting        # direct dispatch on self — user's `def greeting` runs
    writer.push_value(val, "greeting") unless val == Panko::Serializer::SKIP
    writer.pop
  end
end
```

**Why K1 over J or A** (J = init-time dispatcher ivar; A = thread-local
dispatcher cache + Lambda Callable wrapper — both rejected):

- **Per-record cost lowest** — ~40ns (3 ivar writes + direct dispatch) vs
  ~90ns (J) vs ~140ns (A: `Thread.current[]` + `public_send`).
- **Only shape safe for self-recursion** without extra guards. A serializer
  that recurses into itself
  (`CommentSerializer has_many :replies, serializer: CommentSerializer`)
  allocates its own Generated Class instance per nested level under K1.
  J and A both share a dispatcher across recursion depths and would
  clobber `@object` / `@context` / `@scope` mid-walk. The guards required
  to make J/A safe (snapshot/restore, per-depth pool) violate the
  no-hot-path-allocation constraint.
- **Native compat** for `super`, helper methods, `private` methods, and
  `prepend`-ed modules — it's just Ruby method dispatch on `self`.

**Surface changes inside scg**:

- `Panko::CodeGen::Descriptor` gains a `parent_class:` field, defaulting
  to `nil`. Non-Panko callers stay on the existing `Class.new` parent
  (`Object`) and on the Callable contract — no behavioural change for the
  scg test surface.
- `MethodAttribute#body` accepts either a Callable (today's contract,
  kept for non-Panko callers and for fixtures) **or a Symbol** (the user
  method name) when the Descriptor's `parent_class:` is non-`nil`.
- The emitter branches at compile time: Symbol-body emits
  `value = <method_name>` on `self`; Callable-body emits
  `value = @cb_<n>.call(record, context, scope)` as today (with the
  arity-3 widening per the
  [scope-and-context decision above](#both-scope-and-context-survive-pankos-public-dsl)).
- `_write_one` per-call mutation of `@object` / `@context` / `@scope` is a
  bounded deviation from scg's "GC ivars are init-time constants" audit
  pattern. Documented in `docs/code-generation.md` when this lands.

**Surface changes inside Panko**:

- `Panko::Serializer` exposes `attr_reader :object, :context, :scope`
  (or the existing accessor methods, simplified to read directly from
  the ivars the `parent_class` dispatch sets per record).
- `Panko::SerializationContext` is deleted as part of the merge (per the
  [scope-and-context decision](#both-scope-and-context-survive-pankos-public-dsl)).

**Self-recursion gate**: Phase 3.3 lands a regression spec —
`CommentSerializer has_many :replies, serializer: CommentSerializer` with a
method-field that returns `object.body` — verifying that each nested level
sees its own `@object` / `@context` / `@scope`. The spec exists to lock the
`parent_class` dispatch shape in: any future "optimize back to J/A" attempt
trips on it.

### AR `alias_attribute` resolves transparently — no code change

**Decision (2026-05-09 PM)**: Panko's C-extension behaviour where
`alias_attribute :full_name, :name` on an AR model + `attributes :full_name`
on a serializer reads from the underlying `name` column and emits the JSON
key `"full_name"` is preserved post-merge **with no scg-side code change**.
The Panko→scg converter (Phase 2.2) emits
`Attribute(name: :full_name, source: :full_name)` regardless of any AR
alias; correctness comes from Ruby's normal method dispatch.

**Why**: AR installs alias-reader methods on
`<Model>::GeneratedAttributeMethods` at class-definition time. scg's
`AccessClassifier` already returns `:method` for an aliased name (because
`columns_hash` doesn't carry the alias but `method_defined?` does, and
`user_override?` correctly identifies the owner as
`GeneratedAttributeMethods` — i.e. AR-generated, not user-defined). The
emitted `record.full_name` call resolves through AR's alias to
`_read_attribute("name")`. Both Generic and Specialized paths work
correctly today; the C ext's bespoke `attribute_try_invalidate` +
`attribute_aliases` lookup is not needed.

**Measured equivalence and cost**: byte-identical JSON output across
single record, array of 50, nil-aliased value, type-cast values
(datetime / integer / JSON column). Per-aliased-field overhead vs scg's
own no-alias baseline is ~0.8% per field, 4.1% worst-case at 5/5
aliased. scg remains 1.21×–1.29× faster than Panko's C-ext baseline
across all aliased configurations (Panko itself slows ~3.4% when one
attribute is aliased — alias resolution isn't free in either engine).
Harness: `/tmp/alias_bench/bench.rb`.

**Consequence**: Phase 2.2 converter has zero alias-handling logic for
AR `alias_attribute` — nothing to write, nothing to test beyond the
existing Panko alias spec which the codegen path already passes
unchanged. (Distinct from Panko's `aliases({col: :alias_name})` DSL,
which is a class-time rename of the **output** key — that's handled by
scg's existing `Attribute(name:, source:)` split per the Q7 cascade
note in the open-questions doc.) STI/mixed-class serializers behave
sensibly: a class in `models:` that lacks the alias raises
`UnknownSourceError` at compile time (loud), not at runtime.

### `HashWithIndifferentAccess` records resolve transparently — no code change

**Decision (2026-05-10)**: Panko's behaviour where Hash records (plain
or `HashWithIndifferentAccess`) get serialized via per-key Hash lookup
is preserved post-merge **with no scg-side code change**. The Phase 2.2
converter emits a `Panko::CodeGen::Config` with
`hash_record_key_type: :string`, which produces `record["name"]`
lookups in scg's Generic emit path — byte-identical to Panko's
hardcoded C-side `rb_hash_aref(obj, attribute->name_str)`.

**Why**:

- Panko's C ext (`ext/panko_serializer/attributes_writer/hash.c:3-13`)
  dispatches on `BUILTIN_TYPE == T_HASH` (HWIA satisfies — subclass)
  and reads via `rb_hash_aref(obj, attribute->name_str)` —
  string-only, no fallback, no normalization.
- HWIA stores keys as strings internally
  (`ActiveSupport::HashWithIndifferentAccess#convert_key`), so
  Panko's string lookup hits HWIA's storage table directly. HWIA
  support is incidental but reliable.
- scg's Generic path
  (`generators/record_access/generic.rb:67-77, 253-258`) branches on
  `record.is_a?(Hash)` (HWIA satisfies — subclass) and emits
  `record["name"]` under the default `Config#hash_record_key_type:
  :string`. HWIA's overridden `[]` normalizes both Symbol and String
  lookups; plain string-keyed Hashes hit the same path. Both engines
  produce identical output for every Hash shape Panko users feed in.

**Measured equivalence**: 5 input shapes × 2 output modes = 10/10
byte-identical results between Panko's C ext and scg's codegen:
plain Hash with string keys, plain Hash with symbol keys (both
silently emit `null` per field — string lookup misses), HWIA built
from symbols, HWIA built from strings, plain Hash with mixed keys.
Harness: `/tmp/hwia_check/probe.rb`.

**Consequence**:

- Phase 2.2 converter has zero HWIA-handling logic. It emits
  descriptors against scg's existing Generic path.
- Phase 2.2 converter pins the emitted Config to
  `hash_record_key_type: :string` — Panko's DSL has no equivalent
  knob, and string is what Panko's C ext hardcodes.
- Phase 2.1 audit re-runs the HWIA probe against the codegen path
  (parity gate) and ports Panko's three existing HWIA specs
  (`spec/features/hash_serialization_spec.rb` — string-keyed Hash,
  HWIA-from-symbols, HWIA-from-strings). The plain symbol-keyed
  Hash case (currently unpinned in Panko: silent-nil behaviour with
  no spec) gets pinned in Phase 2.1 too — locks the post-merge
  contract for an input shape that's de-facto supported but
  documented nowhere.
- The `Config#hash_record_key_type` knob (`:string` default,
  `:symbol` alternative) **survives the merge as internal
  `Panko::CodeGen::Config` surface**. The Panko-DSL converter pins it
  to `:string` for parity with the C ext, but the underlying
  machinery stays in place — if Panko later grows DSL syntax to
  declare a different record-key shape (mirror of the `models:`
  Specialized-path future under [§ Deferred to post-merge](#deferred-to-post-merge)),
  the codegen layer doesn't need a refit.

**Symbol-keyed plain Hash quirk** (informational, not part of the
decision): both engines silently emit `null` for every field when
fed a `{ name: "x" }` plain Hash — string lookup misses Symbol
storage. Panko has shipped this for years without a spec or doc;
scg inherits the behaviour. If Panko ever wants to "fix" the
silent-nil case (probe both Symbol and String on each lookup),
that's a post-merge feature decision driven by `Config`, not a
merge blocker.

### `Panko::Serializer` instances become reusable

**Decision (2026-05-09 PM)**: the `@used` single-use guard at
`lib/panko/serializer.rb:140` (raises `ArgumentError("Panko::Serializer
instances are single-use")` on second `serialize` / `serialize_to_json`
call) is removed at merge. Sequential reuse —
`s = FooSerializer.new; records.each { |r| s.serialize(r) }` —
becomes a supported pattern that produces correct output per record.

**Why**: the guard was added in commit `cf5c484` (2019, issue #47) as a
safety rail against a C-ext state-leakage bug where the second
`serialize` call returned the first record's data. **Empirical
verification across 8 scenarios** — plain attrs, method fields,
has_one, has_many, filters, context, polymorphic records,
`ArraySerializer` — **shows the bug no longer reproduces in current
Panko**: bypassing the guard with
`serializer.instance_variable_set(:@used, false)` produces output
byte-identical to a fresh-instance baseline on every scenario. The
underlying bug was fixed indirectly somewhere in the C-ext history;
the guard was never retired. Post-merge the C ext is deleted entirely
(Phase 2.6); scg's Generated Class is reusable by design (no per-call
ivar state survives `_write_one`, even under the `parent_class` dispatch's
per-call `@object`/`@context`/`@scope` writes — each call overwrites them
at the top). Consistency: `Panko::ArraySerializer` has never had this
guard, so the contract was already an outlier within Panko itself.

**Surface changes**:

- Public DSL unchanged. `FooSerializer.new(opts).serialize(record)`
  works as today.
- `serializer.serialize(foo_a); serializer.serialize(foo_b)` no
  longer raises; both calls return their respective records' data.
- Two characterization specs are deleted under Phase 2.6's
  test-deletion rule (pre-approved by user, 2026-05-09 PM):
  `spec/features/attributes_spec.rb:252-264` and
  `spec/unit/panko/serializer_spec.rb:180-194`.
- Regression harness: `/tmp/reuse_check/harness.rb` (re-runnable
  pre-merge against the C ext to confirm parity).

**Why this is non-breaking for users**: the documented happy path
(`FooSerializer.new(opts).serialize(record)` — fresh instance per
record) is unchanged. Code that previously raised on the second
iteration of a same-instance loop now produces the correct output
for every iteration. Nobody depends on the raise as a feature; the
two existing specs test the guard itself, not user-visible behaviour.

### Filter co-supply — Panko-side adapter flattens, scg stays strict

**Decision (2026-05-16)**: Panko users keep supplying both `only:` and
`except:` (the existing public API). A Panko-side adapter
(`Panko::FilterAdapter`) flattens co-supplied `(only, except)` into a
single-key Hash using Panko's sequential resolution (`only` then `except`)
**before** handing the result to scg's `Filter.wrap`. scg's strict
co-supply raise (`lib/serializers_code_gen/filter.rb:85-90`) and
`Indexed.build`'s "only wins" fallback (pinned at
`spec/filter_spec.rb:172`) both stay unchanged.

**Why**: keeps Panko-shape concerns in the Panko-side adapter (the
established split — adapter owns translation from Panko shape to scg
shape); scg stays a general-purpose engine with a strict contract.
Empirical bench (`/tmp/cosupply_bench/bench.rb`, 2026-05-16) shows the
two paths are perf-equivalent in the common one-sided case (identical
allocations: 5 obj / 544 B; identical ips within noise) and Path 1 wins
the rare co-supply case on ips (+10%) at the cost of ~4 extra Arrays
per call (≤56 bytes). Choosing Path 1 (adapter flattens) over Path 2
(scg accepts both keys and resolves sequentially) means we don't break
`spec/filter_spec.rb:172`'s pinned "only wins" fallback or remove
scg's strict API surface.

**Adapter scope**: ~50 LoC total — a single combined module
`Panko::FilterAdapter` that owns **both** the co-supply flatten **and**
the Panko-shape → scg-shape translation (Q8.b decision, 2026-05-16).
One entry point (`Panko::FilterAdapter.adapt(only, except, field_index)`)
returns the wrapped `Filter` object ready for the Generated Class.

The flatten is recursive — must walk the filter Hash at every level
because Panko supports co-supply at nested association levels too, and
scg's `validate_no_only_except_co_supply!` raises depth-first
(`lib/serializers_code_gen/filter.rb:91-93`). The shape translation
fuses into the same walk in the co-supply case (no separate
`merge_trees` pass — see the perf footnote).

**Shape translation rules** (Q8.b):

| Panko input | scg output |
|---|---|
| `[:a, :b]` (Array, top-level) | `{only: [:a, :b]}` (or `{except: ...}` for the except side) |
| `{instance: [:a]}` | `{only: [:a]}` |
| `{instance: []}` | `nil` (no-op, matches Panko) |
| `{instance: [:a], comments: [:b]}` | `{only: [:a], comments: {only: [:b]}}` |
| `{comments: [:b]}` | `{comments: {only: [:b]}}` |
| `{comments: {instance: [:b], replies: [:c]}}` | `{comments: {only: [:b], replies: {only: [:c]}}}` |
| `nil` or `{}` | `nil` |
| Non-Array, non-Hash values at any level | ignored (forward-compat with `docs/filters.md § Rules`) |

**Flatten formula** (per level):

| Input | Output |
|---|---|
| `only` empty, `except` empty | `nil` |
| `only` non-empty, `except` empty | `{only: only}` |
| `only` empty, `except` non-empty | `{except: except}` |
| both non-empty | `{only: only - except}` (may be `{only: []}` → all-drop, matches Panko) |

The `{only: []}` edge case is correct: `Set.new` is truthy in Ruby, so
`Indexed.build`'s `drop?` returns `true` for every name → all-drop
filter, matching Panko's narrow-then-reject empty result.

**Phase 3.2 spec gate** (the parity matrix the adapter must satisfy):

1. Top-level co-supply: `{only: [a,b], except: [b]}` → keeps `[a]`.
2. Nested-association co-supply: `{only: {comments: [a,b]}, except: {comments: [b]}}` → comments keeps `[a]`.
3. Mixed: top-level one-sided + nested co-supply.
4. The all-drop edge: `{only: [a], except: [a]}` → drops everything.

**`:instance` namespace clash — preserve Panko's silent behavior**
(Q8.e, 2026-05-16). When a serializer declares a real association named
`:instance` (e.g. `has_one :instance, serializer: InnerSerializer`),
the association is unreachable through the `only:` / `except:` nested
filter shape — Panko's `:instance` key is reserved as the self-level
filter namespace and any `instance:` entry is consumed for parent
attributes. Probe (`/tmp/instance_clash/probe.rb`) confirmed this is
Panko 0.8.5's existing behavior. **The converter preserves it
unchanged**; the limitation is documented as a known limitation in
[merging-into-panko-changes.md § Documented limitation — `has_one
:instance` / `has_many :instance` filters
unreachable](merging-into-panko-changes.md#documented-limitation--has_one-instance--has_many-instance-filters-unreachable),
and a loud-failure-mode revisit is deferred to
[deferred.md § `:instance` namespace clash](deferred.md#instance-namespace-clash--loud-failure-mode).
Rationale: bug-compat is safer than forcing every affected user to
rename a real association at upgrade time; the clash is rare enough
that documenting it is sufficient for the initial merge.

**Adapter runs eagerly per call — no FilterAdapter memoization**
(Q8.c, 2026-05-16). Bench (`/tmp/cosupply_bench/memo_bench.rb`) showed
hash-equality memoization is 2–3× faster than eager when cache hits,
**but** every unique filter Hash adds a permanent cache entry. Apps
with dynamic filter sources (e.g. parsers that convert query-string
params to filter Hashes) would leak memory unboundedly. Eager is
~1 µs per call regardless — small, predictable, safe for every
caller pattern.

**Perf follow-up**: bench shows per-call setup overhead at 1–2 µs in
worst case (cosupply_nested). For single-record serialize paths this
is 2–20% of total render cost. If profiling later flags it as a
regression, the safe optimizations are (a) bounded-LRU memoization with
explicit eviction policy or (b) a Filter-object pool with explicit
reuse semantics — both deliberately out of scope for the initial merge.

### Compile cache stays in Panko

**Decision**: the **Compile** function does **not** memoize results inside the
library. Caching is owned by the caller — i.e., Panko.

**Why**: Panko already owns the caching layer for serializer classes (its DSL
caches compiled serializers per class). Pushing a second cache into the library
would either duplicate or compete with Panko's. Keeping **Compile** as a pure
function makes the library trivially thread-safe and easy to reason about.

**Consequence post-merge**: when this gem folds into Panko, the cache lives at
the Panko-DSL layer. The code-gen layer remains a pure function from
**Descriptor** → **Generated Class**.

**Cache identity — LOCKED Q9 (2026-07-05)**: `(serializer class, output
mode, models-permutation)`. Two corrections from the original
`(serializer class, filter set, mode)`:

- **Filters are out** (Q8.d). `Filter.wrap` runs at runtime inside
  `serialize_*`, returning a `Filter` the compiled class queries via
  `filter.drops?(i)`; same compiled bytes serve every filter set.
- **Model permutation is in** (2026-07-05, user-caught). scg emits
  *different bytes* per `descriptor.models`: a **Generic** class
  (`models: nil`, `is_a?(Hash)` dispatch, serves any record) vs a
  **Specialized** class per model-class set (monomorphic
  `record._read_attribute("col")`, no Hash branch — see
  `generators/record_access/{generic,specialized}.rb`). So one
  `(class, mode)` fans out to `{generic} ∪ {specialized per model class}`.

**Mechanism — per-class copy-on-write Hash, keyed by model class.** Store,
on each serializer class, one ivar per mode (`@_compiled_json` /
`@_compiled_hash`), each a `Hash{ model_class => generated_class }` plus a
generic-fallback slot. Mode lives in the ivar name (statically known at the
call site), so the Hash key is a **single Class object — no composite key,
no per-read allocation**. Bound: `|classes| × 2 × (1 + distinct model
classes seen)` — still a few hundred entries. Specialization is inherently
**lazy** (model classes aren't known until serialize time), so the Hash is
written at runtime under concurrency → reads must not tear against a
concurrent write. **Thread-safety — LOCKED copy-on-write (2026-07-05)**:
lock-free reads off an immutable Hash snapshot; on the rare miss (first
sight of a model class), a `Mutex` guards `dup → insert → atomic ivar swap`,
double-checking under the lock. An MRI `Hash#[]` racing another thread's
`Hash#[]=`/resize is unsafe even under the GVL, so in-place mutation is
out; COW keeps reads lock-free at the measured 24M/s. Read cost (4.0.2+YJIT,
`/tmp/q9_cache_bench/bench2.rb`): **24.0M i/s / 0 alloc** via a class
reader (`sk._compiled_json[rec.class]`), ~5.6× faster than a global
composite-key map (4.25M i/s / 1 Array alloc/read). An optional
monomorphic inline-cache (last-model-class ivars) lifts reads to 29.7M / 0
alloc if single-record throughput ever demands it — deferred until measured.

**Config is an invariant, not a key dimension.** scg's output *also* varies
with `Config` (notably `pool_writer`, which changes emitted source), so
`(class, mode, models)` holds only under the Panko-side invariant that each
serializer compiles with one fixed Config at compile time. If per-request
Config is ever introduced, Config re-enters the key.

**Reopening — LOCKED Q9 (2026-07-05): unsupported, zero invalidation code.**
Reopening a serializer after first use is undefined — no dirty flag, no
version counter, no per-serialize definition check. Class-identity keying
makes Rails/Zeitwerk reload self-heal (reload mints a new class object →
empty per-class Hash → recompile from the edited definition). Only the
manual-reopen-of-a-live-class edge goes stale, which Panko and Rails
already treat as undefined; documented as a limitation in
[merging-into-panko-changes.md](merging-into-panko-changes.md#documented-limitation--reopening-a-serializer-after-first-use-is-unsupported).

**Eviction — LOCKED Q9 (2026-07-05): unbounded, no LRU.** Size is a static
property — `|classes| × 2 × (1 + distinct model classes served)`, a few
hundred entries — not a function of traffic; GC reclaims a class's Hash
with the class. (Contrast Q8.c, where unbounded memoization *was* rejected:
that key was arbitrary runtime filter Hashes; here it's the bounded set of
model classes.) **Q9 fully resolved.**

### Ruby version floor — `>= 3.4` (Q10)

**Decision (LOCKED 2026-07-05)**: the merged gem requires **Ruby >= 3.4**.
This bumps Panko's current `>= 3.1.0`; it *matches scg's existing gemspec*
(`required_ruby_version = ">= 3.4"`) and CI matrix (`[3.4, 4.0]`), so the
engine already runs on 3.4 — no porting. `Data.define` (scg's binding
language feature, 3.2+) is comfortably satisfied.

**Why 3.4, not lower**: 3.4 and 4.0 are the only Ruby lines in **normal
maintenance** (ruby-lang.org branches page, checked 2026-07-05). 3.1
(EOL 2025-03-26) and 3.2 (EOL 2026-04-01) are end-of-life; 3.3 is in
**security maintenance** only (EOL expected 2027-03-31) and is
deliberately dropped — the floor tracks normal-maintenance lines, not
merely non-EOL ones.

**Consequences**: dropping 3.1–3.3 is a compatibility break for Panko
users on those versions → feeds **Q11** (versioning — argues for a major
bump). CI adopts scg's `[3.4, 4.0]` Ruby lanes → feeds **Q12** (CI matrix).
User-visible entry in
[changes.md § Ruby version floor raised to `>= 3.4`](merging-into-panko-changes.md#ruby-version-floor-raised-to--34).

### CI matrix — collapse onto Panko's superset (Q12)

**Decision (LOCKED 2026-07-05)**: the merged gem keeps **Panko's** CI as
the base — it's a superset of scg's. Both already use **Appraisals** and
both already test **Rails `[7.2, 8.0, 8.1]`** (Panko's Rails floor is
already 7.2), so there is no tooling migration and no Rails-axis
reconciliation. Changes to Panko's incumbent CI:

- **Narrow Ruby to `[3.4, 4.0]`** — deletes Panko's `3.2` / `3.3` lanes per
  Q10 (§ Ruby version floor).
- **Add the `ruby 4.0 × rails 7.2` exclude** from scg's matrix (Rails 7.2
  predates Ruby 4.0); Panko's `tests.yml` currently lacks it.
- **Keep Panko's `database_matrix.yml`** (mysql / trilogy DB-driver
  coverage) — scg has sqlite only, and the codegen engine's Specialized
  path reads AR columns, so real-driver coverage matters.
- **Drop the `clang-format` lint step** when the C extension is deleted
  (Phase 2.6); keep `standardrb`.
- scg's `Appraisals` / `gemfiles/` are absorbed into Panko's; nothing
  unique in scg's CI survives except the exclude rule.

No dual-lane transition — the matrices are already ~identical. Gemspec
hygiene graft: declare an explicit `activesupport >= 7.2` floor (Panko's
gemspec currently pins none, though only 7.2+ is tested).
