# ActiveRecord attribute-access benchmark — Ruby 4.0.2 + YJIT

Benchmark script: [`ar_access_bench.rb`](ar_access_bench.rb)
Raw stdout: [`ar_access_yjit_output.txt`](ar_access_yjit_output.txt)

The numbers below come from a single run of `bundle exec ruby --yjit ar_access_bench.rb`
on Ruby 4.0.2 with YJIT enabled. `benchmark-ips` was run with warmup=3s,
time=5s per variant. Each variant reads **all 9 columns** of a `Post` and
returns them as an array, so the reported ips is "full-record reads per
second," not per-attribute.

## 1. Environment

| | |
| --- | --- |
| Ruby             | `ruby 4.0.2 (2026-03-17 revision d3da9fec82) +YJIT +PRISM [arm64-darwin25]` |
| ActiveRecord     | 8.1.3 |
| JITs             | YJIT=on, ZJIT=off |
| Kernel (`uname -a`) | `Darwin yosi 25.3.0 Darwin Kernel Version 25.3.0: Wed Jan 28 20:51:28 PST 2026; root:xnu-12377.91.3~2/RELEASE_ARM64_T6041 arm64` |
| macOS (`sw_vers -productVersion`) | Darwin 25.3.0 (`sw_vers` was not reachable from the sandboxed shell; Darwin 25 corresponds to macOS "Tahoe" 26.x — per the `env` block reported by the harness) |
| CPU arch         | arm64 (Apple Silicon) |

## 2. Results

Columns:
- **ips** — full-record (9-column) reads per second
- **× slowest** — ips relative to the slowest variant in the same table
- **allocs/call** — objects allocated per single call (via `memory_profiler`)
- **bytes/call** — bytes allocated per single call

### 2.1 Persisted record (loaded via `Post.first`)

Sorted by ips descending. Slowest = `attrs_bt + manual cast` (146,785 ips).

| # | Variant                               |         ips |  × slowest | allocs/call | bytes/call |
|---|---------------------------------------|------------:|-----------:|------------:|-----------:|
| 1 | `_read_attribute`                     |   4,428,235 |    30.17×  |           1 |        160 |
| 2 | `method_dispatch`                     |   3,891,908 |    26.51×  |           1 |        160 |
| 3 | `read_attribute_before_type_cast`     |   3,212,296 |    21.88×  |           1 |        160 |
| 4 | `read_attribute`                      |   3,095,263 |    21.09×  |           1 |        160 |
| 5 | `record['col']`                       |   2,912,973 |    19.84×  |           1 |        160 |
| 6 | `attributes_before_type_cast[]`       |   2,230,416 |    15.19×  |           2 |        624 |
| 7 | `record[:col]`                        |   1,531,753 |    10.43×  |          10 |        520 |
| 8 | `attributes[]`                        |     667,719 |     4.55×  |           7 |      1,504 |
| 9 | `read_bt + manual cast`               |     152,407 |     1.04×  |          40 |      3,232 |
|10 | `attrs_bt + manual cast`              |     146,785 |     1.00×  |          41 |      3,696 |

### 2.2 Non-persisted record (built via `Post.new(...)`)

Sorted by ips descending. Slowest = `attributes[]` (911,346 ips).

| # | Variant                               |         ips |  × slowest | allocs/call | bytes/call |
|---|---------------------------------------|------------:|-----------:|------------:|-----------:|
| 1 | `_read_attribute`                     |   4,128,890 |     4.53×  |           1 |        160 |
| 2 | `method_dispatch`                     |   3,688,270 |     4.05×  |           1 |        160 |
| 3 | `read_attribute_before_type_cast`     |   3,166,723 |     3.47×  |           1 |        160 |
| 4 | `read_attribute`                      |   3,052,770 |     3.35×  |           1 |        160 |
| 5 | `record['col']`                       |   2,740,099 |     3.01×  |           1 |        160 |
| 6 | `attributes_before_type_cast[]`       |   2,269,771 |     2.49×  |           2 |        624 |
| 7 | `read_bt + manual cast`               |   1,795,475 |     1.97×  |           2 |        320 |
| 8 | `record[:col]`                        |   1,499,603 |     1.65×  |          10 |        520 |
| 9 | `attrs_bt + manual cast`              |   1,491,448 |     1.64×  |           3 |        784 |
|10 | `attributes[]`                        |     911,346 |     1.00×  |           4 |      1,064 |

## 3. Correctness observations

Lines quoted from `=== correctness (persisted|non-persisted) ===` in
[`ar_access_yjit_output.txt`](ar_access_yjit_output.txt).

### 3.1 What does `_read_attribute` return for the enum `status`?

Persisted:

```
_read_attribute   ...  | "published"
```

Non-persisted:

```
_read_attribute   ...  | "published"
```

`_read_attribute("status")` returns the **mapped label string** (`"published"`),
i.e. the enum goes through the same type cast the reader method would apply.
In other words, on AR 8.1 `_read_attribute` and `read_attribute` are
semantically equivalent for enum columns — the old Panko assumption that
`_read_attribute` gives you the raw integer is no longer true.

### 3.2 What does `attributes_before_type_cast` / `read_attribute_before_type_cast` return?

For a **persisted** record (values came back from SQLite as strings/integers):

```
attributes_before_type_cast[]    => 1 | "A short title" | "A longer body..." | 1 | "2026-04-21 14:31:54.821199" | "2026-04-21" | 12345 | 4.25 | 1
read_attribute_before_type_cast  => 1 | "A short title" | "A longer body..." | 1 | "2026-04-21 14:31:54.821199" | "2026-04-21" | 12345 | 4.25 | 1
```

- `published` (boolean) → `1` (DB representation)
- `published_at` (datetime) → `"2026-04-21 14:31:54.821199"` (string, no TZ)
- `publish_date` (date) → `"2026-04-21"` (string)
- `rating` (decimal) → `4.25` (Float — NOT BigDecimal; sqlite3 adapter returned a Float)
- `status` (enum) → `1` (raw DB integer, no mapping applied)

For a **non-persisted** record (`Post.new(**attrs)`), the raw values are
whatever you passed in — i.e. already typed Ruby objects:

```
attributes_before_type_cast[]    => nil | "A short title" | ... | true | 2026-04-21 17:31:54 +0300 | Tue, 21 Apr 2026 | 12345 | 0.425e1 | "published"
```

- `published` → `true` (the Boolean you passed, not `1`)
- `published_at` → `Time` object
- `publish_date` → `Date` object
- `rating` → `BigDecimal("4.25")` (because that's what was handed in)
- `status` → `"published"` (the string label)

This is why `CAST["status"].call(h["status"])` returns `"draft"` for the
non-persisted record: the raw value is already `"published"`, the cast does
`"published".to_i → 0`, and then maps `0 → "draft"`. **The manual cast
path is type-fragile: it assumes the DB-string shape and silently corrupts
data on non-persisted records.**

### 3.3 Persisted vs non-persisted — do raw values diverge?

Yes, significantly. `attributes_before_type_cast` for a persisted record
returns DB-serialized strings/ints (the adapter's raw row, minimally
unpacked). For a non-persisted record it returns whatever Ruby object the
user handed to `Post.new` — the same objects that the type-cast readers
would return. So the "raw" path has two completely different shapes per
column depending on persistence state. Any serializer emitting manual cast
code must either call the typed reader or apply both sides of each cast
defensively.

## 4. Analysis

### 4.1 Top 3 by ips

Persisted:
1. `_read_attribute` — 4.43M ips (225.8 ns/call)
2. `method_dispatch` — 3.89M ips (256.9 ns/call) — 1.14× slower
3. `read_attribute_before_type_cast` — 3.21M ips (311.3 ns/call) — 1.38× slower

Non-persisted: same ordering, slightly compressed.
1. `_read_attribute` — 4.13M ips
2. `method_dispatch` — 3.69M ips — 1.12× slower
3. `read_attribute_before_type_cast` — 3.17M ips — 1.30× slower

`_read_attribute` beats the commonly-used `read_attribute` by ~1.43×
(persisted) / 1.35× (non-persisted), and beats plain `method_dispatch`
(e.g. `record.title`) by ~1.14× / 1.12×.

### 4.2 Is `before_type_cast + manual cast` faster than `_read_attribute`?

**No — it is dramatically slower, and the gap is enormous for persisted
records.**

Persisted:

| Variant                   |       ips | vs `_read_attribute` |
|---------------------------|----------:|---------------------:|
| `_read_attribute`         | 4,428,235 |              —       |
| `read_bt + manual cast`   |   152,407 |    **29.06× slower** |
| `attrs_bt + manual cast`  |   146,785 |    **30.17× slower** |

Non-persisted (cast is a near-no-op because values are already typed):

| Variant                   |       ips | vs `_read_attribute` |
|---------------------------|----------:|---------------------:|
| `_read_attribute`         | 4,128,890 |              —       |
| `read_bt + manual cast`   | 1,795,475 |     2.30× slower     |
| `attrs_bt + manual cast`  | 1,491,448 |     2.77× slower     |

For persisted records, the Ruby-side cast has to actually do work
(`Time.parse` on a string, `to_d` on a Float, integer→label lookup,
boolean string comparisons, etc.). That pushes allocations to ~40 objects
/ 3.2–3.7 KB per call — two orders of magnitude more than `_read_attribute`.

### 4.3 Persisted vs non-persisted — ranking / magnitude

Ranking of the "real" access forms (method_dispatch, _read_attribute,
read_attribute, record['col'], both before_type_cast forms) is stable
across persistence state. Magnitudes move a bit but not meaningfully —
all within ~8% of their persisted counterparts.

The **only dramatic shifts** are in the manual-cast variants: they go
from ~30× slower than the winner on persisted records to ~2.5× slower on
non-persisted records, because the cast lambdas effectively short-circuit
on already-typed input (e.g. `Time.parse` isn't called on a `Time`
object). That alone should warn us: the "optimization" only helps when
the raw value is the cheap DB form, which is not a guarantee the library
gets to make.

`attributes[]` also moves: it's the slowest on non-persisted (911k ips)
and 8th on persisted (668k ips). The dup-and-type-cast-all-columns cost
of `#attributes` is roughly constant, so relative position depends on
how expensive the other variants are.

### 4.4 Allocation surprises

- `attributes[]` allocates **7 objects / 1,504 B** on a persisted record
  (4 / 1,064 B on non-persisted). That's the `Hash#dup`-with-casting of
  the full `@attributes` set — a fresh hash plus cast values — paid once
  per call regardless of how many columns you read. At 668k ips it's the
  dominant cost.
- `record[:col]` surprisingly allocates **10 objects / 520 B per call**.
  AR's symbol-keyed access converts each symbol to a string
  (`sym.to_s`) internally; that's 9 string allocations + the return
  array. The clean fix from a code-gen standpoint is to always emit
  string keys.
- `_read_attribute`, `read_attribute`, `read_attribute_before_type_cast`,
  `record['col']`, and `method_dispatch` all allocate exactly **1 object
  / 160 B** per call — and that one allocation is the 9-element return
  array built by the benchmark itself. Per-attribute allocation is zero
  on the hot path. This is the key result: **modern AR readers are
  allocation-free for column-backed attributes on Ruby 4 + YJIT.**
- The `attrs_bt + manual cast` / `read_bt + manual cast` variants explode
  to 40–41 allocations / ~3.2–3.7 KB on persisted records. Every
  `Time.parse`, `Date.parse`, `BigDecimal.to_d`, and the status-label
  hash lookup contributes. This is the cost the legacy Panko trick was
  intended to dodge by bypassing AR's cast pipeline — but AR's pipeline
  is now faster than the Ruby-side cast.

## 5. Recommendation

### 5.1 Which access form should the code-gen library emit?

**Emit `record._read_attribute("col")` for column-backed attributes with
no reader override.** It is:

- The fastest variant tested (4.43M / 4.13M ips persisted / non-persisted).
- Allocation-free per attribute (1 allocation in the benchmark is the
  return array; in a generated serializer the caller is already building
  its output buffer, so marginal cost is zero).
- Returns **type-cast** values, so the generated code does not need a
  second cast stage, and does not need to special-case enums, booleans,
  dates, or decimals.
- Stable across persisted and non-persisted records (same ordering, same
  semantics).

Fallback order, if `_read_attribute` ever disappears or is deemed too
"private": `method_dispatch` (column reader method, 1.14× slower) →
`read_attribute` (string key, 1.43× slower). Never emit `record[:col]`
(symbol key — 2.89× slower on persisted, 10 allocations/call) and never
emit `record.attributes[...]` (6.63× slower persisted).

### 5.2 Is the legacy Panko `before_type_cast + manual cast` trick still worth its complexity?

**No.** Keep the trick out of the code-gen library.

The historical justification for `before_type_cast + manual cast` was
that AR's type-cast path was slow on Ruby 2.x/3.x without YJIT, and
Panko could beat it by reading the DB-raw value and doing the cast in
tight C or hand-tuned Ruby per column. On Ruby 4.0.2 + YJIT with AR
8.1.3 that premise has fully inverted: `_read_attribute` is **29–30×
faster** on persisted records and **2.3–2.8× faster** even on
non-persisted records where the cast is nearly a no-op. The trick now
also carries real correctness cost — the "raw" value has *different
shape* depending on persistence state (Boolean-as-int vs Boolean,
String-timestamp vs Time, Integer-enum vs label), so any manual cast has
to defend against both shapes or silently corrupt data (our non-persisted
run returns `"draft"` for a status that every other variant reports as
`"published"`). Complexity up, performance down, correctness worse —
there's no scenario left where the manual-cast path pays off for this
library.
