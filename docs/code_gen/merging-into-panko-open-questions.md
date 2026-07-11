# Merging into Panko — open questions

Working surface for the design grilling that produced
[merging-into-panko.md](merging-into-panko.md). Each item below is **unresolved**
as of the last session; resolutions get moved into the main plan as they're
locked.

The grilling continues with `/grill-me` — see § Resume prompt at the bottom.

---

## Pause state (2026-07-05)

**🎉 Grilling complete — every question resolved or deferred.** Q1–Q10 and
Q12 resolved; **Q11 (versioning) ⏸️ deferred** to release time (analysis
parked in § Q11 below). This session (2026-07-05) locked **Q9**
(compile-cache: identity `(class, mode, models-permutation)`; per-class
copy-on-write Hash keyed by model class; COW thread-safety; reopening
unsupported; unbounded eviction), **Q10** (Ruby floor `>= 3.4`, matching
scg's existing gemspec), and **Q12** (CI → collapse onto Panko's superset
matrix). Merge base = Panko `master`; the `ruby-impl-perf-codegen` branch
is dead.

**scg-side prerequisites — ✅ SHIPPED (verified 2026-07-05).** The
context+scope work (S17) is landed — `validators/callable_arity.rb` is
`ALLOWED_ARITIES = 0..3` and `scope:` is a kwarg in both `serialize_one` /
`serialize_many` emit paths (json + hash). K1 method-field dispatch prep
(S18) is also merged. `deferred.md § Pre-Panko-merge` is empty (both
promoted + shipped). The design grilling is done and the prerequisites are
in — the next move is executing the [phase plan](merging-into-panko.md)
starting at **Phase 1** (git-merge scg under `Panko::CodeGen`).

### Prior pause — Q8 (resolved 2026-05-16)

Q8 sub-questions resolved 2026-05-16:

- **Q8.a — filter co-supply path: Path 1 locked.** Panko-side adapter
  (`Panko::FilterAdapter`) flattens co-supplied `(only, except)` into a
  single-key Hash before scg's `Filter.wrap`. scg's strict raise and
  `Indexed.build` "only wins" fallback both stay. Empirical perf bench at
  `/tmp/cosupply_bench/bench.rb` confirmed Path 1 is identical to Path 2
  in the common one-sided case (5 obj / 544 B, same ips within noise),
  +10% ips in the rare co-supply case (cost: ~4 extra Arrays per call).
- **Q8.b — filter shape mapping: Option A locked.** Single combined
  `Panko::FilterAdapter` module owns both the co-supply flatten and the
  Panko-shape → scg-shape translation. One entry point
  (`Panko::FilterAdapter.adapt(only, except, field_index)`) returns the
  wrapped Filter ready for the Generated Class. ~50 LoC total.
- **Q8.c — eager vs memoized: EAGER locked.** No FilterAdapter
  memoization layer. Memoization bench (`/tmp/cosupply_bench/memo_bench.rb`)
  showed hash-equality memo is 2–3× faster on cache hits, but every
  unique filter Hash adds a permanent cache entry — apps with dynamic
  filter sources (query-string parsers, params-derived filters) would
  leak memory unboundedly. Eager is ~1 µs per call, safe for every
  caller pattern.
- **Q8.d — canonical cache key form: MOOT.** Investigation under Q8.c
  proved the Compile cache is **filter-agnostic** (verified by reading
  `lib/serializers_code_gen/compiler.rb`, `generator.rb`,
  `descriptor.rb` — none of them reference filters). The compile cache
  key is `(serializer class, output mode)`, not `(class, filter tuple,
  mode)`. No filter-shape canonicalization needed. **Boundary decision
  correction flagged for Q9** — see
  [merging-into-panko.md § Compile cache stays in Panko](merging-into-panko.md#compile-cache-stays-in-panko).
- **Q8.e — `:instance` namespace clash: preserve Panko's silent
  behavior + document.** Probe (`/tmp/instance_clash/probe.rb`)
  confirmed a real `has_one :instance` is unreachable through the
  filter Hash today. Converter preserves the existing behavior
  unchanged. Limitation documented at
  [merging-into-panko-changes.md § Documented limitation](merging-into-panko-changes.md#documented-limitation--has_one-instance--has_many-instance-filters-unreachable);
  loud-failure-mode revisit deferred at
  [deferred.md § `:instance` namespace clash](deferred.md#instance-namespace-clash--loud-failure-mode).

All five decisions captured at
[merging-into-panko.md § Boundary decisions — Filter co-supply](merging-into-panko.md#filter-co-supply--panko-side-adapter-flattens-scg-stays-strict).

**Still-not-landed blocker (carried over from 2026-05-09):** scg-side
context+scope first-class is **not yet shipped** (last verified
2026-05-14: `validators/callable_arity.rb` still pins
`ALLOWED_ARITIES = 0..2`; `serialize_one` / `serialize_many` still lack
the `scope:` kwarg in both emit paths). Q8.a didn't need it. Q8.b–Q8.e
don't strictly need it either. The broader merge plan does — Q7's K1
close is predicated on it.

**Carried over (still-not-landed):** scg-side context+scope
first-class is **not yet shipped** (last verified 2026-05-14:
`validators/callable_arity.rb` still pins `ALLOWED_ARITIES = 0..2`;
`serialize_one` / `serialize_many` still lack the `scope:` kwarg in
both emit paths). Q9 doesn't strictly need it; the broader merge plan
does (Q7's K1 close is predicated on it).

After Q8 closes, Q9–Q12 remain untouched (compile-cache lifecycle, Ruby
version floor, versioning, CI matrix).

---

## Q8. Filter mapping — Panko `only:` / `except:` → scg filter set

**Status (2026-05-16): ✅ fully resolved.**
- **Q8.a (co-supply path):** Path 1 locked (Panko-side adapter
  flattens).
- **Q8.b (mapping shape):** Option A locked (single combined
  `Panko::FilterAdapter` module).
- **Q8.c (eager vs memoized):** EAGER locked (no FilterAdapter memo —
  avoids unbounded cache growth for dynamic-filter apps).
- **Q8.d (canonical cache key form):** MOOT — Compile cache is
  filter-agnostic; key is `(class, mode)`. Correction flagged for Q9.
- **Q8.e (`:instance` namespace clash):** preserve Panko's silent
  behavior + document; loud-failure-mode revisit deferred.

All five decisions captured at
[merging-into-panko.md § Boundary decisions — Filter co-supply](merging-into-panko.md#filter-co-supply--panko-side-adapter-flattens-scg-stays-strict).

### Context

Panko's runtime kwargs `only:` and `except:` support nested association
filtering:

```ruby
PostSerializer.new(only: { instance: [:title], posts: [:body] })
```

scg has filter sets that drive `Filters::Indexed` vs `Filters::None`
selection at compile time. The boundary decision says the compile cache is
keyed on `(serializer class, filters tuple, output mode)` — so the filter
shape translates into a deterministic, hashable cache key.

### Q8.a — co-supply path (resolved 2026-05-16)

Compressed history:

- **Empirical findings (2026-05-14, harness `/tmp/cosupply_check/`):**
  Panko's filter resolution is **uniformly sequential**
  (`apply_attribute_filters` and `apply_association_filters` apply
  `only` then `except`); the early-returning `apply_fields_filters`
  branch is dead code. scg's `Indexed.build` has an **"only wins"
  fallback** pinned at `spec/filter_spec.rb:172` (calling
  `Indexed.build({only:[:f0], except:[:f1]}, ...)` keeps `f0` only).
  scg's `Filter.wrap` raises uniformly on co-supply
  (`lib/serializers_code_gen/filter.rb:85-90`).
- **Two reconciliation paths considered:**
  1. **Path 1 (locked):** Panko-side adapter flattens before
     `Filter.wrap`. scg stays unchanged. ~30 LoC adapter; recursive
     because scg validates co-supply depth-first.
  2. **Path 2 (rejected):** scg drops the raise; `Indexed.build`
     switches from "only wins" to sequential. Rejected because it
     invalidates `spec/filter_spec.rb:172` and removes a deliberate
     scg API surface.
- **Perf bench (2026-05-16, harness `/tmp/cosupply_bench/`):** confirmed
  Path 1 is not a regression vs Path 2. Common one-sided case: 5 obj /
  544 B allocated, identical ips within noise. Rare co-supply case:
  Path 1 +10% ips, +4 Arrays. See
  [merging-into-panko.md § Filter co-supply](merging-into-panko.md#filter-co-supply--panko-side-adapter-flattens-scg-stays-strict)
  for the full decision and the Phase 3.2 spec gate.

### Test requirement — `:instance` namespace preservation (locked 2026-05-09)

Panko's nested filter shape reserves `:instance` as the self-level
keyword:

```ruby
{ instance: [:a], foo: [:b] }
# :a applies to the serializer's own attributes;
# :b applies to a has_one/has_many association named :foo.
```

The split happens at
`panko_serializer/lib/panko/serialization_descriptor.rb:140-149`:
`filters.fetch(:instance, [])` for self-level, `filters.except(:instance)`
for nested. Whatever Q8 resolution lands, the `:instance` semantic must
survive the converter — `instance:` is not just one association name
among many; it's a reserved namespace key.

**Spec requirement** (gate-level: Phase 3.2 — "Filtered serialization
specs green"; co-located with the converter built in Phase 2.2):

1. **Self-level + nested coexist.** `{ instance: [:a], foo: [:b] }` on
   a `has_one :foo` serializer applies `:a` to the parent attributes
   and `:b` to the nested serializer's attributes. Output is
   byte-identical between pre-merge Panko and post-merge codegen.
2. **`instance:` only.** `{ instance: [:a] }` filters the parent and
   leaves all associations unfiltered (parity with Panko's
   `filters.except(:instance)` returning `{}`).
3. **Nested only.** `{ foo: [:b] }` (no `instance:` key) leaves the
   parent unfiltered and applies `:b` to the nested serializer.
4. **Empty hash.** `{}` is a no-op (matches Panko's
   `return [], {} if filters.empty?`).
5. **Both `only:` and `except:` co-supplied.** Per Q8.a Path 1:
   adapter flattens at every nesting level using `only - except`,
   producing a single-key Hash. Parity matrix: top-level co-supply,
   nested-association co-supply, mixed (top-level one-sided + nested
   co-supply), and the all-drop edge (`{only:[a], except:[a]}` → drops
   everything).

**Open in Q8.e**: a user defines a real has_one/has_many association
literally named `:instance` — see Pause state.

---

## Q9. Compile cache lifecycle (Panko side)

**Status (2026-07-05): ✅ fully resolved.** All sub-questions locked:
cache identity `(class, mode, models-permutation)`; mechanism = per-class
copy-on-write Hash keyed by model class (mode in the ivar name, single-Class
key, 24M i/s / 0 alloc on 4.0.2+YJIT); thread-safety = copy-on-write
(lock-free reads, `Mutex`+swap on the rare first-sight-of-model miss);
reopening = unsupported (documented limitation); eviction = unbounded.
Merge base = Panko `master` (C-ext lineage); the `ruby-impl-perf-codegen`
branch is dead (user, 2026-07-05) — its in-tree codegen engine is rejected,
but its *cache architecture* was useful prior art.

**Context.** [Boundary decision](merging-into-panko.md#compile-cache-stays-in-panko)
puts the cache on the Panko side. scg's compile is a pure function —
same input → equivalent output. The cache is **greenfield**: `master`
has no `lib/panko/code_gen/` and no compiled-artifact cache — today
`SerializationDescriptor.build` re-`duplicate`s the canonical class-level
`_descriptor` and applies filters on **every** serialize call, so there
is no staleness surface. The merge introduces one (a compiled class
cached from the descriptor).

### Sub-questions

- **Cache identity — ✅ LOCKED (2026-07-05).** `(serializer class, output
  mode, models-permutation)`. Filter-agnostic (Q8.d). **Model dimension
  added (user-caught):** scg emits different bytes per `descriptor.models`
  — Generic (`nil`, `is_a?(Hash)` dispatch) vs Specialized per model-class
  set (`record._read_attribute`), so `(class, mode)` fans out to
  `{generic} ∪ {specialized per model class}`. Config stays an invariant
  (fixed at compile time), not a key dimension; if per-request Config is
  ever introduced it re-enters the key. Locked in
  [merging-into-panko.md § Compile cache stays in Panko](merging-into-panko.md#compile-cache-stays-in-panko).
- **Mechanism — ✅ per-class Hash (user, 2026-07-05).** One ivar per mode
  on the serializer class (`@_compiled_json`/`@_compiled_hash`), each a
  `Hash{ model_class => generated_class }` + generic slot. Single-Class key
  (mode encoded in the ivar name) → no composite key, **no per-read
  alloc**. Read cost (4.0.2+YJIT-only per user policy, `bench2.rb`):
  **24.0M i/s / 0 alloc** via a class reader (`sk._compiled_json[rec.class]`),
  ~5.6× faster than a global composite-key map (4.25M i/s / 1 Array
  alloc/read — the composite `[sk,mode,model]` key is what kills it).
  Optional monomorphic inline-cache (last-model-class ivars) → 29.7M / 0
  alloc; deferred until single-record throughput demands it. (Corrects the
  earlier "single ivar, 29.7M/6.4×" framing, which assumed one compiled
  class per `(class, mode)` and missed the model-permutation fan-out.)
- **Thread-safety — ✅ LOCKED: copy-on-write Hash (user, 2026-07-05).**
  The Hash is written **lazily at runtime** (model classes unknown until
  serialize), under concurrency — a read must not tear against a concurrent
  insert (MRI Hash `[]` during another thread's `[]=`/resize is unsafe even
  under the GVL). COW: lock-free reads off an immutable snapshot (stays
  24M/s); on the rare miss (first sight of a model class) a `Mutex` guards
  `dup → insert → atomic ivar swap`, double-checking under the lock.
  Rejected: `Concurrent::Map` per class (safe but reads drop to 4.25M,
  5.6× slower); `Mutex` on every access (slowest). Prior art: Panko's dead
  branch dodged this with a thread-local working descriptor + `||=`
  single-ivar compiled class — no runtime-grown shared Hash; the
  model-keyed Hash reintroduces the concern, hence COW.
- **Class reopening — ✅ LOCKED: unsupported (user, 2026-07-05).** No
  invalidation machinery (no dirty flag / version counter / per-serialize
  definition check) — keep it simple. Class-identity keying makes it safe
  for the real path: Zeitwerk reload = `remove_const` + re-require → **new
  class object** (probe `/tmp/q9_reopen/`: object_id 16→24, `equal? ==
  false`) → fresh empty per-class Hash → recompile from the edited
  definition. Only stale case: manually reopening the **same live class**
  after first serialize — undefined in Panko today, matches Rails' stance
  and scg's immutable-Descriptor assumption. Behavior change vs master
  (which rebuilds from `_descriptor` every call, so it'd reflect a reopen)
  only in that undefined edge; documented at
  [changes.md § Documented limitation — reopening](merging-into-panko-changes.md#documented-limitation--reopening-a-serializer-after-first-use-is-unsupported).
  (Secondary note: if the mechanism ever reuses object_id-keyed
  thread-locals, those leak the old slot until thread death — N/A for the
  class-ivar Hash.)
- **Eviction — ✅ LOCKED: unbounded, no LRU (user, 2026-07-05).** Size is a
  static property — `|classes| × 2 × (1 + distinct model classes served)`,
  a few hundred entries — not a function of traffic. Nothing to evict; GC
  reclaims a class's per-class Hash with the class object. Consistent with
  Q8.c's rejection of unbounded memoization: that key was arbitrary runtime
  filter Hashes (unbounded); this key is the bounded set of model classes.

---

## Q10. Ruby version floor

**Status (2026-07-05): ✅ RESOLVED — floor `>= 3.4`.**

**Decision.** The merged gem requires **Ruby >= 3.4**. Bumps Panko's
`>= 3.1.0`; matches scg's *existing* gemspec (`required_ruby_version =
">= 3.4"`) and CI matrix (`[3.4, 4.0]`) — verified this session, so the
engine already runs on 3.4 with no porting. `Data.define` (3.2+) satisfied.

**Rationale.** 3.4 and 4.0 are the only lines in **normal maintenance**
(ruby-lang.org branches page, checked 2026-07-05). 3.1 (EOL 2025-03-26)
and 3.2 (EOL 2026-04-01) are EOL; **3.3 is *security maintenance* only**
(EOL expected 2027-03-31) — deliberately dropped. The floor tracks
normal-maintenance lines, not merely non-EOL ones (user, 2026-07-05).

**Cross-links.** Compatibility break (drops 3.1–3.3) → **Q11** (argues
major bump). CI adopts `[3.4, 4.0]` → **Q12**. User-visible entry seeded
in [changes.md](merging-into-panko-changes.md#ruby-version-floor-raised-to--34).
Locked in [merging-into-panko.md § Ruby version floor](merging-into-panko.md#ruby-version-floor--34-q10).

---

## Q11. Versioning

**Status (2026-07-05): ⏸️ DEFERRED by user — decide at release time.** Not
resolved; user will pick the number when the release is imminent. Analysis
below is decision-ready so it needn't be re-derived.

**Grounding gathered (2026-07-05).**
- Panko has been **0.x its entire life** — 57 release tags (0.7.x → 0.8.5),
  never a 1.0. It treats 0.x as its stable line; jumping to 1.0 reverses a
  long, deliberate stance.
- **`2.0.0` is semver-invalid from 0.8.5** — there's no 1.x to break from;
  the first stable release *is* 1.0.0. Real choice is **0.9.0 vs 1.0.0**
  (unless the user wants a non-standard marketing jump).
- Accumulated breaking changes (from changes.md): **Ruby floor `>= 3.4`**
  (locked, Q10) and **datetime/time output format** (Breaking, but its
  *decision is deferred post-merge* — output bytes not finalized). Plus
  C-ext removal (packaging), `SerializationContext` deletion (internal),
  instances-reusable + reopening-unsupported (non-breaking).

**Crux.** Committing to 1.0.0 = committing to a stable public API/output,
but the **datetime output contract isn't finalized** — 1.0 now risks a
fast 2.0 if datetime later shifts.

**Recommendation (not locked).** Ship the merge as **0.9.0** (honest 0.x
breaking bump — in pre-1.0 semver the *minor* is the breaking axis), let
the C→Ruby rewrite soak and resolve datetime, **then cut 1.0.0** as an
earned "API + output committed" milestone. Counter-case: 1.0.0 now marks
the rewrite as a line in the sand, *if* datetime is nailed before release
or a fast 2.0 is acceptable.

---

## Q12. CI matrix

**Status (2026-07-05): ✅ RESOLVED — collapse onto Panko's superset CI.**

**Finding.** The two matrices are already ~identical: **both use
Appraisals**, and **both already test Rails `[7.2, 8.0, 8.1]`** (Panko's
Rails floor is already 7.2). scg's CI is a subset of Panko's (Panko adds a
DB-driver matrix). So no dual-lane transition is needed.

**Decision.** Keep Panko's CI as the base and:
- narrow Ruby to `[3.4, 4.0]` (drops Panko's `3.2`/`3.3` lanes, per Q10);
- graft in scg's `ruby 4.0 × rails 7.2` exclude (Rails 7.2 predates Ruby
  4.0; Panko's `tests.yml` lacks it);
- keep Panko's `database_matrix.yml` (mysql/trilogy — the Specialized path
  reads AR columns, so real-driver coverage matters);
- drop the `clang-format` lint step at C-ext removal (Phase 2.6), keep
  `standardrb`;
- absorb scg's `Appraisals`/`gemfiles/`; declare an explicit
  `activesupport >= 7.2` gemspec floor (currently unpinned).

Locked in [merging-into-panko.md § CI matrix](merging-into-panko.md#ci-matrix--collapse-onto-pankos-superset-q12).

---

## Historical pause states (preserved)

Earlier session pauses that have since resolved. Kept here as a thin
audit trail; full decision rationale lives in
[merging-into-panko.md](merging-into-panko.md).

- **2026-05-14**: paused mid-Q8.a recommending Path 1 pending user lock.
  Resolved 2026-05-16 (this session) — Path 1 locked after perf bench.
- **2026-05-09 PM**: paused mid-Q7 awaiting scg-side context+scope work.
  Q7 itself resolved same day (K1 dispatch locked) once scope-preservation
  was reframed as a no-API-break migration. Scg-side prerequisite work
  remains outstanding (see "Still-not-landed blocker" in current pause
  state). Q7-cascade items SKIP-unification and column-alias translation
  were captured in [§ Q7](#q7-method-field-translation--panko-instance-methods--scg-method-fields)
  in the prior revision and re-homed under the merge plan's Phase 2.

---

## Resume prompt (paste into a fresh session)

```
We're partway through grilling a plan to merge serializers-code-gen into Panko.
The session paused 2026-05-16 with Q8 fully resolved (Q8.a–Q8.e all
locked, Q8.d ruled moot). Active question on resume: Q9 (Compile cache
lifecycle).

Working directory: /Users/yosi/code/projects/serializers-code-gen
Panko source:     /Users/yosi/code/projects/panko_serializer (branch: master)

## Read first
- docs/merging-into-panko.md — locked decisions and phase plan; the
  "Filter co-supply" boundary decision absorbs all Q8 decisions; the
  "Compile cache stays in Panko" decision has a pending correction
  note flagged for Q9 (cache key is (class, mode), not (class, filter
  set, mode))
- docs/merging-into-panko-open-questions.md — start at "Pause state
  (2026-05-16)" for the live state; Q9 listing has the corrected
  cache-key bullet
- docs/merging-into-panko-changes.md — user-visible changes log
  (includes Q8.e's documented limitation entry)
- docs/deferred.md § Pre-Panko-merge — scg-side context+scope work
  status (still not landed as of 2026-05-14); § No fixed revisit date
  includes Q8.e's loud-failure-mode revisit entry

## State summary

- Q1–Q7 resolved; items 1–8 of the merge investigation closed.
- Q8 fully resolved 2026-05-16:
  - Q8.a Path 1 (adapter flattens co-supplied (only, except))
  - Q8.b Option A (single combined `Panko::FilterAdapter` module)
  - Q8.c EAGER (no adapter memo — avoids unbounded cache growth)
  - Q8.d MOOT (Compile cache is filter-agnostic)
  - Q8.e preserve Panko's silent `:instance` clash + document
- Q9 inherits a boundary-decision correction (cache key is
  (class, mode)). Open sub-questions: cache key lock,
  thread-safety, class-reopening semantics, eviction.
- scg-side context+scope first-class work is NOT yet shipped
  (validators/callable_arity.rb still 0..2; no scope: kwarg in
  serialize_one/serialize_many). Q9 doesn't strictly need it;
  the broader merge plan does.
- Q10–Q12 untouched (Ruby version floor, versioning, CI matrix).

## Investigation pattern (locked 2026-05-09 PM)
Investigate empirically before bringing options. Read the relevant code
across both repos, run a probe / harness when behaviour is in question,
then present options grounded in evidence — including perf (ips +
allocations) before presenting trade-offs. Harnesses live at /tmp/<name>/.
Existing: alias_bench/, reuse_check/, hwia_check/, cosupply_check/,
cosupply_bench/, instance_clash/.

## Workflow rules
- ONE question at a time. Close before moving on.
- scg-side work          → docs/deferred.md, marked [important].
- Panko-side decisions   → docs/merging-into-panko.md (if locked) OR
                           docs/merging-into-panko-open-questions.md.
- User-visible changes   → also seed in docs/merging-into-panko-changes.md.
- Never run `git push`. User runs all pushes.
- ADHD focus: tight on a single item, never batch.

## Begin
Open Q9. First, lock the cache-key correction inherited from Q8.c/Q8.d
(update the boundary decision text in docs/merging-into-panko.md from
"(class, filter set, mode)" to "(class, mode)"). Then walk the
remaining sub-questions: thread-safety, class-reopening semantics,
eviction policy.

/grill-me
```
