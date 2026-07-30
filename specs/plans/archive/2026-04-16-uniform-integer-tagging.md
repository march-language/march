# Uniform Low-Bit Integer Tagging for Polymorphic Values

> **For agentic workers:** checkbox (`- [ ]`) syntax tracks task progress.

**Goal:** Give March a zero-cost runtime discriminator between heap pointers and small scalars stored in polymorphic (type-erased) positions, so `march_incrc` / `march_decrc` / `march_value_to_string` / generic `==` / generic `compare` never dereference an integer as a `march_hdr *`. Concretely: `Check.all(Gen.int(0, 10000), ...)` must not SIGSEGV; more generally, `List(Int)`, `Map(Int, _)`, `GenTree(Int)`, etc. become sound under the full RC/equality machinery.

**Tech Stack:** OCaml (compiler), C11 (runtime), LLVM IR (codegen)

---

## Diagnosis

Polymorphic ADT fields and function parameters have LLVM type `ptr`. Compile-time type variables (`TVar "_"`) that survive monomorphisation get the same `ptr` representation. When a scalar value flows into such a position, the codegen boxes it with `inttoptr i64 n to ptr` (lossless for integers, reinterprets the bit pattern for floats via `bitcast double → i64`).

Perceus then emits `march_incrc` / `march_decrc` on the extracted value based on the compile-time type (`TVar "_"` counts as "heap-carrying"). The C runtime's `IS_HEAP_PTR` macro guards the dereference:

```c
#define IS_HEAP_PTR(p) \
  ((uintptr_t)(p) >= 4096u && (intptr_t)(p) > 0)
```

Guard 1 (`>= 4096`) rules out low integers (0–4095). Guard 2 (`> 0`, added in commit d2cf09e) rules out negative integers. **There is no guard for positive integers in `[4096, 2^62]`** — those values pass `IS_HEAP_PTR` and `march_incrc` dereferences them as a header, causing SIGSEGV. `Gen.int(0, 10000)` reliably triggers this (~60% of generated values).

Related symptoms (same root cause, different call sites):
- `march_value_to_string(poly_arg)` crashes on Int / Bool stored polymorphically when the actual value has its sign bit clear and is `>= 4096`.
- Generic `==` / `compare` / `hash` on polymorphic fields have the same exposure when implemented as pointer-deref-based comparison.

The only correct fix is a **runtime discriminator** — a bit pattern that `IS_HEAP_PTR` can read without dereferencing. Low-bit tagging is the standard approach (OCaml, V8, Scheme systems): integers are stored as `(n << 1) | 1`, so their low bit is always 1; heap pointers from `march_alloc` (backed by `calloc`) are 8- or 16-byte aligned, so their low bit is always 0. `IS_HEAP_PTR(p)` becomes `(p & 1) == 0 && …`. Zero instructions on the hot path (LLVM folds `shl 1` + `or 1` + `inttoptr` into a single `inttoptr` of a constant for literal values, and into a 2-instruction sequence otherwise).

**Why the narrow "tag only in coerce" attempt failed** (see reverted commit in this session): tagging the `coerce ("i64", "ptr")` and untagging in `coerce ("ptr", "i64")` is locally consistent, but many polymorphic-ptr values flow through paths that bypass `coerce`:

- Function-reference wrappers (`llvm_emit.ml:1077`, `:1205`, `:3947`) wrap an i64-returning fn into a ptr-returning closure via raw `inttoptr`.
- `__try_call` in the runtime calls the apply function via a function pointer typed `int64_t (*)(void *, int64_t)` and stores the raw i64 return into `Result.Ok`. If the wrapper tagged but the runtime didn't untag, Bool `true` (1) becomes stored as `3` and `not(passed)` misbehaves.
- `march_value_to_string` etc. receive the polymorphic ptr and walk it based on runtime tag introspection — no untag point.

Either **every** boundary tags/untags, or **none** does.

---

## Design

**Tag scheme:** low bit 1 = immediate integer (or integer-representable scalar); low bit 0 = heap pointer (aligned malloc result).

Encode / decode:
- `box_int(n : i64) → ptr`: `inttoptr ((n << 1) | 1)`. Sign-preserving on a two's-complement machine. Loses 1 bit of Int range (`i63`).
- `unbox_int(p : ptr) → i64`: `ashr (ptrtoint p) by 1`. Matches the sign-preserving shift above.
- Same encoding for Bool (stored 0/1 → 1/3), Char (small code points), and any scalar that fits in `i63`.

**What NOT to tag:**
- Real heap pointers (already low-bit 0 via calloc alignment).
- Float, when stored in a polymorphic slot: `shl` destroys the sign/exponent bits. **Float in polymorphic slots must be boxed** (allocate a 24-byte heap cell holding the raw double, low-bit-0 pointer). This is a new rule; current code just inttoptrs the bitcast i64 and relies on `IS_HEAP_PTR` accidentally rejecting it.

**Runtime contract:** `IS_HEAP_PTR(p) == ((p & 1) == 0 && (uintptr_t)p >= 4096u && (intptr_t)p > 0)`. The additional 4096 / sign guards are defense-in-depth for Float and for any uninitialised memory the codegen might emit.

**Bit-range invariant:** March `Int` is `i63` (range `-2^62 … 2^62 - 1`) when it flows through a polymorphic slot. Within a monomorphic scope (e.g. `fn sum(xs: List(Int)) : Int`) values stay as `i64` and the full range is preserved — this plan only changes polymorphic boundaries.

**Interaction with monomorphisation:** tagging eliminates the correctness hazard, but mono is still the perf win. When `GenTree(Int)` is fully monomorphised the field is `i64` directly and no tag work happens. The tag scheme is the safety net for the polymorphic leak paths that mono can't close.

---

## Scope — every boxing / unboxing site

### OCaml-side boxing (tag in LLVM IR)

Every site that produces a ptr from a scalar needs `shl 1 | or 1` **unless** the scalar is already a real heap pointer:

- [ ] `lib/tir/llvm_emit.ml:945` — `coerce (scalar, "ptr")` case. Specialise out `("i64", "ptr")` to tag; keep `("double", "ptr")` boxed (see below); keep other scalars going through a tagged path.
- [ ] `lib/tir/llvm_emit.ml:941` — `coerce ("ptr", scalar)` case. Specialise out `("ptr", "i64")` to untag via `ashr`; keep `("ptr", "double")` unboxing (see below); keep `i1` / `i32` via tagged ashr.
- [ ] `lib/tir/llvm_emit.ml:1077` — closure wrapper for i64-returning extern. Tag the i64 return before `inttoptr`.
- [ ] `lib/tir/llvm_emit.ml:1205` — second closure wrapper. Same.
- [ ] `lib/tir/llvm_emit.ml:3947` — third closure wrapper. Same.
- [ ] `lib/tir/llvm_emit.ml:1081, :1209, :3950` — double-returning wrappers: replace `bitcast double → i64 → inttoptr` with `call @march_alloc_float(double)` returning an aligned heap cell.

### March-side unboxing in specialised contexts

When a March-level function is monomorphised to take/return `Int` (not `ptr`), calls into/out of polymorphic interfaces must tag/untag at the ABI boundary. Current codegen already does this implicitly via `coerce`; the new tagged version is a drop-in as long as the boundary is identified consistently.

- [ ] Audit `lib/tir/llvm_emit.ml` for every `inttoptr` / `ptrtoint` outside `coerce`. Any that crosses a polymorphic ABI boundary must adopt the tag. `grep -n "inttoptr\|ptrtoint" lib/tir/llvm_emit.ml` gives the list; annotate each with a one-word comment: `tag`, `raw` (C ABI), or `float-box`.

### C runtime — tag-aware hot paths

Any C function that receives a polymorphic `void *` argument and inspects the pointee must check `IS_HEAP_PTR` first.

- [ ] `runtime/march_runtime.c:128` — update `IS_HEAP_PTR` to add `((uintptr_t)(p) & 1u) == 0` as the **first** clause (short-circuits before the 4096 / sign check on the hot RC path).
- [ ] `runtime/march_runtime.c:119–188` — `march_incrc`, `march_decrc`, `march_decrc_freed`, `march_free`, `march_incrc_local`, `march_decrc_local`. Already use `IS_HEAP_PTR`; re-check that the updated macro short-circuits correctly.
- [ ] `march_value_to_string`, `march_eq`, `march_compare`, `march_hash`, and any other generic runtime function that dispatches on `march_hdr->tag`: check `IS_HEAP_PTR(p)` first. On the immediate path, extract the integer as `(intptr_t)p >> 1` and format/compare as Int.
- [ ] `__try_call` (runtime/march_runtime.c): the apply function returns whatever its compile-time return type was — if `Bool`, the wrapper has already tagged it; if `String`, it's a raw ptr. `__try_call` just stores the return in `Result.Ok` as a polymorphic field; this **already works** with uniform tagging (the value is correctly tagged/untagged at compile-time boundaries, and `__try_call` only needs to not interfere). Add a regression test that returns a heap value vs. a scalar to confirm.

### Prelude / stdlib — re-verify under tagging

Most stdlib code is monomorphic or receives values through explicit types; the tag is invisible. The risky spots are intrinsics that inspect pointer bits directly:

- [ ] `stdlib/list.march`, `stdlib/map.march`, `stdlib/hamt.march` — these store polymorphic values in fields; they don't inspect the bits, so they should Just Work. Spot-check by running `forge test` on each.
- [ ] Any `extern` declaration that returns `Int` into a polymorphic position — see Monomorphic/polymorphic wrapper rule above.

### Float boxing — `march_alloc_float`

- [ ] `runtime/march_runtime.c` — add:
  ```c
  void *march_alloc_float(double d) {
      march_float_box *b = (march_float_box *)march_alloc(24);
      b->value = d;
      return b;
  }
  double march_unbox_float(void *p) {
      return ((march_float_box *)p)->value;
  }
  ```
- [ ] `runtime/march_runtime.h` — declare `march_float_box = { march_hdr hdr; double value; }` (24 bytes, naturally aligned).
- [ ] `lib/tir/llvm_emit.ml` — replace `bitcast double → i64 → inttoptr` with `call ptr @march_alloc_float(double %v)` in the `coerce ("double", "ptr")` case and all double-returning wrappers.
- [ ] Float RC: the box itself is heap-allocated, so normal `march_incrc` / `march_decrc` on the ptr works. Perceus treats it like any other heap value.

---

## Implementation Phases

### Phase 1 — prove the tag scheme end-to-end on Int alone

Do the minimum coordinated change so `Check.all(Gen.int(0, 10000), ...)` passes, without tackling Float.

- [ ] Update `IS_HEAP_PTR` to include the low-bit check (first clause, before `>= 4096`).
- [ ] Update `coerce ("i64", "ptr")` and `coerce ("ptr", "i64")` to tag / untag.
- [ ] Update all three wrapper emitters (i64 case) to tag.
- [ ] Verify: negative ints, zero, positive ints of all sizes, literal 0 passed as a polymorphic ptr (currently represents null-ish default).
- [ ] Run `forge test` + all existing alcotest tests. Any regression pinpoints a missed boxing site.
- [ ] Write regression tests:
  - `Check.all(Gen.int(0, 10000), fn n -> n >= 0 && n <= 10000)` — previously SIGSEGV'd.
  - `Check.all(Gen.int(-2^30, 2^30), fn n -> n + 0 == n)` — stress negatives and positives.
  - Compile `let m : Map(Int, String) = ... Map.insert(m, 100000, "hi")` — polymorphic field with a large Int key.

**Exit criterion:** full test suite green; three new regression tests pass; `bench/*` benchmarks within 2% of pre-tag baseline (Int-in-poly-position is rare enough that overall impact should be noise).

### Phase 2 — polymorphic runtime functions

- [ ] `march_value_to_string`: prepend an `IS_HEAP_PTR` check; handle the immediate path by calling `march_int_to_string((intptr_t)p >> 1)`.
- [ ] `march_eq`: if both sides fail `IS_HEAP_PTR`, bit-equality on the raw value is already correct (tagged ints compare equal iff their underlying values are equal). If one side heap, one side immediate, they can never be equal — return 0. If both heap, current logic stands.
- [ ] `march_compare`: same structure as `march_eq`, with ordering.
- [ ] `march_hash`: for immediates, hash the untagged value; for pointers, current logic.
- [ ] Test: `Map(Int, _)` used as a hash key with large ints; `==` on polymorphic fields containing mixed-sign ints.

**Exit criterion:** `Gen.int(-10^9, 10^9)` paired with every polymorphic runtime entry point (`==`, `to_string`, `hash`, `compare`) runs 1000 iterations without crash.

### Phase 3 — Float boxing

- [ ] Introduce `march_float_box` and `march_alloc_float` / `march_unbox_float`.
- [ ] Update `coerce ("double", "ptr")` to heap-box; update `coerce ("ptr", "double")` to unbox.
- [ ] Update all double-returning wrapper emitters to box.
- [ ] Update `march_value_to_string` to detect float boxes (distinct tag in the header) and call `march_float_to_string`.
- [ ] Regression test: `Check.all(Gen.float(-1000.0, 1000.0), fn x -> x + 0.0 == x)` — currently untested in a compiled binary.

**Exit criterion:** `Gen.float` + `Check.all` runs 1000 iterations; `Map(Float, _)` works (even though Floats are usually not ideal map keys).

### Phase 4 — `i63` bit-range enforcement

Tagged Ints lose one bit. The language-visible `Int` is still documented as 64-bit in monomorphic positions but becomes 63-bit when passing through a polymorphic slot. This is subtle.

- [ ] Decide: do we guarantee 63-bit Int everywhere (for simplicity) or document the boundary (for perf)?
  - **63 everywhere**: `Int.max_value` = `2^62 - 1`, `Int.min_value` = `-2^62`. Simplest mental model. Matches OCaml.
  - **64 monomorphic, 63 polymorphic**: zero perf cost in the common case but user-visible footgun (a value round-tripped through `List(Int)` loses a bit).
- [ ] Update `Int.max_value` / `Int.min_value` in the prelude.
- [ ] Update docs in `specs/progress.md` and `syntax_reference.md`.
- [ ] Decide compiler behavior on overflow at the box site: silently truncate, trap, or statically error on literals that can't fit? Recommended: trap at runtime via `__builtin_saddl_overflow` when `-Odebug`, silently truncate under `-O2+`.

**Exit criterion:** the Int.max_value literal round-trips through `List(Int)` correctly.

### Phase 5 — documentation & followups

- [ ] Update `specs/progress.md`: note tagging scheme under "Runtime layout".
- [ ] Update `syntax_reference.md` if the Int range changes become user-visible.
- [ ] `runtime/march_runtime.h`: document the tag convention at the top.
- [ ] Benchmark suite: confirm no regression in `bench/tree_transform`, `bench/list_ops`, `bench/binary_trees` (per CLAUDE.md regression mapping). Perceus/FBIP changes are the primary concerns; tagging adds 2 instructions per poly-boundary crossing.
- [ ] Consider: a `--no-tag` compiler flag for benchmarking / debugging.

---

## Risks & Mitigations

**Risk:** a polymorphic runtime function dereferences a tagged integer because it was written before tagging existed and only checks the constructor tag.
- **Mitigation:** `IS_HEAP_PTR` is the single gate. Every runtime function that reads `march_hdr->tag` must call `IS_HEAP_PTR` first. Audit with `grep 'march_hdr.*tag' runtime/*.c` and annotate each.

**Risk:** a March program stores a pointer-valued literal that happens to have bit 0 set (e.g., C-level opcodes passed through `extern`).
- **Mitigation:** `extern` results come through typed wrappers; pointers from March code come from `march_alloc` which is always aligned. Bit-0 collisions can only come from raw FFI, which is out of scope for polymorphic slots.

**Risk:** the `shl 1` truncates a value the programmer didn't expect to truncate.
- **Mitigation:** overflow detection under `-Odebug` (see Phase 4); well-documented bit-range invariant.

**Risk:** LLVM fails to fold the tag/untag sequence and we lose performance.
- **Mitigation:** inspect LLVM output on a hot loop (e.g. `List.map` over `List(Int)`); confirm `shl` + `or` + `inttoptr` collapse to a single mov-with-constant. If not, move tagging behind an always-inline helper.

**Risk:** incremental rollout (Phase 1 before Phase 2) leaves `march_value_to_string` broken for Ints-in-poly-positions.
- **Mitigation:** Phase 1 and Phase 2 must land together. Phase 3 (Float) can be separate.

---

## Alternative Approaches (considered and rejected)

**A. Fix monomorphisation to eliminate all `TVar "_"` leaks.**
The "right" theoretical fix: if every `TVar "_"` is fully resolved before codegen, fields are typed correctly and no polymorphic storage is needed. Rejected because:
- Higher-rank / existential types are fundamentally non-specialisable.
- Closures captured at polymorphic call sites can't be re-specialised without running mono inside the closure's environment.
- Even if mono could close the common case, we'd still need a fallback for the remaining 1% — and that fallback is the tagging scheme anyway.

**B. Boxed ints (heap cell for every `Int` in polymorphic position).**
Correct but ~3× slower on a List(Int) fold. Rejected.

**C. High-bit tag (bit 47 or 48).**
Works on x86-64 user space but collides with pointer-tagging in some JITs and with kernel address space on some OSes. Low-bit is more portable.

**D. Do nothing; trust programmers to avoid the patterns that break.**
Rejected: `Check.all(Gen.int(0, 10000), ...)` crashing is a footgun. Property testing is a feature.

---

## Test Plan

**Unit-level (alcotest):**
- Direct coerce round-trips: tag then untag, confirm value preserved for boundary cases (0, ±1, ±4095, ±4096, ±2^30, ±2^62-1).
- `IS_HEAP_PTR` returns expected answer on: tagged ints, real heap pointers, NULL, kernel addresses, negative ints.

**Integration (forge test):**
- `Check.all(Gen.int(0, 10000), ...)` — Bug 3 regression.
- `Check.all(Gen.int(-10^9, 10^9), ...)` — full-range stress.
- `Map(Int, String)` and `Map(Int, Int)` — hash, eq, compare via tagged keys.
- `List(Int)` round-trip through `to_string` — `march_value_to_string` path.
- `Gen.tuple2(Gen.int, Gen.int)` — heap-allocated polymorphic tuple with two tagged fields.

**Benchmarks (`bench/*.march`):**
- `tree_transform.march` — Perceus / FBIP sensitivity.
- `list_ops.march` — closure allocation, tagged Ints.
- `binary_trees.march` — RC churn.
- Accept ≤2% regression on each; investigate if larger.

---

## Open Questions

1. **Bit-range invariant visibility:** do we commit to 63-bit Int everywhere (OCaml-style) or keep 64-bit monomorphic / 63-bit polymorphic? Recommend 63-bit everywhere for consistency.
2. **Feature flag for the rollout?** A `-fno-int-tag` flag would help bisect any regression during Phase 1. Low cost to add; high value during debugging.
3. **FFI boundary:** C extern returning an `int64_t` that's stored in a polymorphic field needs tagging at the extern wrapper. Already in scope; call out explicitly in docs so stdlib FFI authors get it right.
