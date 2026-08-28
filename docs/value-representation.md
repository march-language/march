---
layout: docs
title: Value Representation (compiler internals)
nav_order: 95
permalink: /docs/value-representation/
---

# Value Representation Contract

> **Compiler internals.** This documents how the compiler lays out values in
> memory, for contributors to the compiler, not for using March. Learning or
> evaluating the language? Skip this.

This is the compiler-internals reference for how March values are laid out in
memory and on the wire between passes: the object header, the tagged-scalar
scheme, which slots are erased vs concrete, closure calling convention, and the
RC contract for in-place record update. It exists because every rule below was
independently rediscovered as a bug at least once (see the History appendix).
None of this is new policy: each section **cites the owning module** as the
source of truth and narrates around it. Where a doc comment is quoted, that
comment governs; if this page and the code disagree at any point, the code
comment wins and this page is stale.

Audience: anyone touching `lib/tir/llvm_emit.ml` and friends, or debugging a
"works in the interpreter, crashes/corrupts when compiled" report.

---

## 1. The object header (`march_hdr`)

Every heap-allocated March value shares a 16-byte header, defined once in
`runtime/march_runtime.h`:

```c
typedef struct { int64_t rc; int32_t tag; int32_t pad; } march_hdr;
```

| Offset | Size | Field | Meaning |
|---|---|---|---|
| 0  | 8 | `rc`  | reference count (`int64_t`, atomic RC ops cast to `_Atomic int64_t*`) |
| 8  | 4 | `tag` | constructor tag (which variant; `0` for single-shape types) |
| 12 | 4 | `pad` | alignment filler; **repurposed** as a record-shape id for records (see `march_record_shape_intern`) |
| 16+ | 8/field | fields | one 8-byte slot per field, `n` fields → `16 + n*8` bytes total |

`lib/tir/llvm_ctx.ml`'s `alloc_size n = 16 + n * 8` is this same arithmetic
expressed again as the one pure size formula every allocation site computes from; the
individual `getelementptr` offsets (`i64 8` for tag, `i64 12` for the
record-shape pad, `16 + i*8` per field) are inline literals repeated at each
`llvm_emit.ml` emit site (`emit_load_tag`/`emit_store_tag`/`emit_load_field`/
`emit_store_field`/`emit_heap_alloc`/`emit_stack_alloc`) rather than routed
through a helper, because those sites are the ones with the historical
back-references; `llvm_ctx.ml`'s comment above `alloc_size` was verified
against `runtime/march_runtime.h:11` directly on this doc's writing date
(2026-07-03); the two still agree byte for byte.

**Claim 1: verified.** `march_alloc(i64 32)` for a 2-field value (tuple,
2-field record, or 1-fn-ptr+1-fv closure struct) is exactly `16 + 2*8`. See
§3 Probe A and §5 Probe D below; both show `call ptr @march_alloc(i64 32)`
for their respective 2-field allocations, confirming the same header+stride
formula underlies tuples, records, and closure structs alike.

`march_string` (declared immediately below `march_hdr` in the same header)
shares this 16-byte prefix on purpose, so string values can be examined for
`tag`/`rc` the same way any other heap cell can before the `len`/`data[]`
suffix is interpreted.

---

## 2. The tagged-immediate scheme and the conditional-untag law

**Governing text:** `lib/tir/llvm_ctx.ml`'s `emit_tag_scalar` / `emit_untag_scalar`
/ `emit_untag_known_scalar` doc comments (lines ~384–458). This section
narrates; those comments are the law verbatim.

Polymorphic/generic slots in March (tuple fields, closure free-variable
fields, generic ADT payloads, dynamically-shaped record fields) are typed
`ptr` at the LLVM level regardless of what they actually hold, because the
same slot must be able to hold either a heap pointer or a scalar (`Int`,
`Bool`, `Atom`). The runtime's `IS_HEAP_PTR` macro (`runtime/march_runtime.c`,
historically documented around lines 139–156 of an earlier revision;
currently the tag-scheme comment + macro sit at lines 137–155) states the
scheme these slots share:

```c
/* Tag scheme:
 *   immediate integer n  → stored as ptr = (n << 1) | 1  (low bit = 1)
 *   heap pointer p       → stored as ptr = p             (low bit = 0)
 *
 * Guards (in order, short-circuit):
 *   1. low bit == 0: any value with bit 0 set is an immediate — reject fast.
 *   2. addresses below one page (4096) are never valid heap allocations.
 *   3. values with the sign bit set are never valid heap pointers on any
 *      supported 64-bit ABI. */
#define IS_HEAP_PTR(p) \
    (((uintptr_t)(p) & 1u) == 0 && (uintptr_t)(p) >= 4096u && (intptr_t)(p) > 0)
```

`march_alloc` (backed by `calloc`) always returns an address at least
8-byte-aligned, so a real heap pointer's low bit is always `0`. An immediate
scalar is tagged `(n << 1) | 1`, always odd. The two representations can
never collide.

**The law, stated as three helpers (`llvm_ctx.ml`), each with an exact
job:**

- **`emit_tag_scalar`**: unconditional tag on the way *into* a generic slot:
  `shl 1`, `or 1`, `inttoptr`. Used whenever an `i64` (or `i1`/scalar) is
  about to be stored somewhere typed `ptr`.
- **`emit_untag_scalar`**: **conditional** untag reading *out of* a generic
  slot that may hold either a tagged scalar or a real heap pointer flowing
  through a scalar-typed view (e.g. dynamically-typed record/alist code with a
  static type that lies about the runtime value): `and 1` to test the low bit,
  `ashr 1` computed unconditionally, then `select` on the bit test. An odd
  value is untagged by the shift; an **even** value is preserved **verbatim**:
  it is a full pointer bit pattern, not `p >> 1`. This makes tag↔untag a
  lossless roundtrip for every bit pattern that can appear in such a slot.
  **Never apply this to a value already known to be a plain heap pointer with
  no scalar view**; restore those with a bare `inttoptr`, not this helper.
- **`emit_untag_known_scalar`**: **unconditional** untag for a payload
  *proved* tagged by construction (a newtype or niche payload that
  `emit_tag_scalar` tagged going in, per `Repr.payload_needs_tag`): plain
  `ptrtoint` + unconditional `ashr 1`, no `and`/`icmp`/`select`, because there
  is no other bit pattern to guard against at that specific program point.

The `coerce` function's `("ptr","i64")` / `("i64","ptr")` cases are the two
call sites most programmers will actually hit: `coerce ctx "ptr" v "i64"` goes
through `emit_untag_scalar` (conditional); `coerce ctx "i64" v "ptr"` goes
through `emit_tag_scalar` (unconditional tag, since going *in* there is never
an ambiguity to resolve).

**Claim 2: verified (IR).** A tuple `(41, 2)` destructured back to `Int`
compiles the field-read side as the full four-instruction conditional
sequence (`and`/`icmp`/`ashr`/`select`), matching `emit_untag_scalar`
exactly:

```llvm
%fv16 = load ptr, ptr %fp15, align 8
%cv17 = ptrtoint ptr %fv16 to i64
%cv18 = and i64 %cv17, 1
%cv20 = icmp ne i64 %cv18, 0
%cv19 = ashr i64 %cv17, 1
%cv21 = select i1 %cv20, i64 %cv19, i64 %cv17
```

(Probe: `/tmp/w4-kapitsa-probe1-tuple.march`, `--emit-llvm`; see transcript
item 1.)

**Claim 3: verified (behavior).** The same program, compiled and run,
prints the arithmetically correct sum (`43` for inputs `41,2` shifted by a
runtime-derived offset): the tag/untag roundtrip is not just present in the
IR but semantically transparent. (Transcript item 2.)

---

## 3. UNIFORM vs NATURAL slots

Two representations coexist for the same March type depending on **where**
the value sits:

- **UNIFORM** (generic/erased slot): tuple fields, closure free-variable
  fields, generic ADT payloads (`TVar` fields), dynamically-shaped record
  fields reached through `record_get`/`record_put`/`record_from_list`. Scalar
  values here are stored **tagged**, `(n<<1)|1`, in a `ptr`-typed slot,
  because the slot's static type is erased and must discriminate scalar vs.
  heap-pointer at runtime (§2).
- **NATURAL** (concrete/monomorphic slot): record fields and ADT fields with a
  type that is statically known at the allocation site. Scalar values here are
  stored **untagged**, as a plain `i64`/`double` in an `i64`/`double`-typed
  slot; there is no ambiguity to resolve because the static type already
  tells every reader what the bit pattern means.

This is not a documentation nicety: mixing the two up is exactly the B5 and
the `record_put`-uniform-handoff bug families (§7). A NATURAL-repr even `Int`
≥ 4096 shares its exact bit pattern with a plausible heap address; only the static field
type (record shape) disambiguates it. A UNIFORM slot resolves the same
ambiguity dynamically via the odd/even tag.

**Floats in UNIFORM slots: the open exception.** A `Float` in a UNIFORM
slot is *today* stored as its raw IEEE-754 bits bitcast into the `ptr`
slot, untagged, and decoded by the reader's static type. This is **unsound
against generic code**: the raw bits are even and in the canonical range,
so `IS_HEAP_PTR` accepts them: a generic RC op writes into `*(3.5)`
(SIGSEGV) and a generic `<=` integer-compares the bits (correct for
positive floats by IEEE coincidence, backwards for negatives). The fix
(`specs/plans/archive/2026-07-13-float-boxing-design.md`) is to **box** a Float
crossing an erasure boundary in a `MARCH_FLOAT_TAG` (-3) heap cell, making
a UNIFORM slot uniformly heap-or-tagged and `needs_rc (TVar _)` truly
sound. The runtime box API (`march_alloc_float`/`march_unbox_float`,
value-aware `march_poly_eq`/`march_poly_compare`) landed additively as
stage 1; the codegen flip that populates UNIFORM slots with boxes is
staged (decision-gated). Until it lands, the monomorphism restriction
keeps unannotated let-bound lambdas monomorphic so generic float
comparators never reach a UNIFORM Float slot.

**Claim 4: verified (IR), Probe A (UNIFORM).** `let t = (n+40, n+1)` (tuple,
runtime-derived so the constant-folder cannot eliminate it) allocates a
2-field cell and stores **both** fields tagged, as `ptr`:

```llvm
%hp20 = call ptr @march_alloc(i64 32)
...
%cv24 = or i64 %cv23, 1
%cv25 = inttoptr i64 %cv24 to ptr
%fp26 = getelementptr i8, ptr %hp20, i64 16
store ptr %cv25, ptr %fp26, align 8      ; UNIFORM: tagged, ptr-typed slot
```

(Probe: `/tmp/w4-kapitsa-probe1-tuple.march`.)

**Claim 5: verified (IR), Probe B (NATURAL).** `type Point = { x: Int, y:
Int }`; `{ x: a, y: b }` built from runtime-derived `a`/`b` allocates a
2-field cell and stores both fields as plain `i64`, untagged:

```llvm
%hp20 = call ptr @march_alloc(i64 32)
...
%ld22 = load i64, ptr %$t27191.addr
%fp23 = getelementptr i8, ptr %hp20, i64 16
store i64 %ld22, ptr %fp23, align 8      ; NATURAL: untagged, i64-typed slot
```

(Probe: `/tmp/w4-kapitsa-probe2-record.march`.) Both probes compile and run
to the arithmetically-correct answer (transcript items 3–6); this isn't
just an IR-shape curiosity, it's the representation the rest of the pipeline
depends on being right.

---

## 4. Closure struct layout and the uniform-ptr apply ABI

**Governing text:** `lib/tir/tir_names.ml`'s `is_apply_fn` doc comment (the
ABI contract) and `lib/tir/defun.ml`'s `lift_lambda` doc comment (the struct
layout); implementation in `lib/tir/llvm_calls.ml`'s `clo_wrap_define`.

**Struct layout** (`defun.ml`): every closure struct's field 0 is the apply
function pointer (`TPtr TUnit`, opaque); fields 1..N are the captured free
variables, in capture order. An apply wrapper (`Tir_names.apply_fn_name`,
format `<fn>$apply$<uid>`) takes the closure pointer as parameter 0
(`Tir_names.clo_param_name`, `"$clo"`) followed by the lambda's original
parameters, and loads each free variable from `$clo` via `Tir_names.fv_field`
(`"$fv" ^ i`, 1-based for closures) at entry.

**The ABI** (`is_apply_fn`'s doc, quoted): *"these are dispatched indirectly
through a closure struct whose fn-pointer is type-erased, so all wrappers
for a given source `(a) -> b` MUST share one calling convention: the generic
ptr ABI (scalar results tagged via the i64->ptr coercion; heap pointers pass
through unchanged; every call site reads the result as ptr). An apply
function's first parameter is also always the closure struct (`$clo`); the
closure-apply ABI CONSUMES that argument (ownership transfers to the
callee)."* This uniform-return-as-`ptr` rule is why `clo_wrap_define`
(`llvm_calls.ml`) exists at all: a closure that only wraps a named
top-level function (no captures) still needs a trampoline that tags its
concrete return value before returning, so indirect callers can `ptr`-dispatch
it identically to a real lambda apply-wrapper: an i64-returning wrapper
tags `(n<<1)|1`, a double-returning wrapper bitcasts into the ptr slot, a
void wrapper returns `ptr null`, and a ptr-returning wrapper passes through.
This is the exact fix class of bug B11 (§7): a wrapper that skips this
tagging step returns a raw i64 where every caller expects a tagged one, and
a `Bool`-returning predicate reads back inverted.

**Claim 6: verified (IR + behavior).** `make_adder(n) = fn x -> x + n`
lifts to a closure struct `$lam...` with 2 fields:

```llvm
%hp4 = call ptr @march_alloc(i64 32)          ; 16 + 2*8: fn ptr + 1 fv
store ptr @$lam27190$apply$3662, ptr %fp6      ; field 0: apply fn ptr
store i64 5, ptr %fp7                          ; field 1 ($fv1 "n"): NATURAL (concrete Int)
...
define ptr @$lam27190$apply$3662(ptr nonnull dereferenceable(16) %$clo.arg, i64 %x.arg) {
  ...
  %ld30 = load ptr, ptr %$clo.addr
  call void @march_incrc_local(ptr %ld30)      ; $clo at arg 0
  %fp32 = getelementptr i8, ptr %ld31, i64 24  ; field 1 = $fv1
  %fv33 = load i64, ptr %fp32, align 8         ; NATURAL load: concrete Int field
```

and the call site untags the apply wrapper's `ptr` return with the full
`emit_untag_scalar` sequence even though the closure's logical return type is
concrete `Int`; the uniform-return ABI applies regardless of the closure's
static signature. Running `add5 = make_adder(5); add5(37)` prints `42`.
(Probe: `/tmp/w4-kapitsa-probe6-closure.march`; transcript item 7.)

Note the closure struct's own free-variable field is stored NATURAL here
(`store i64 5`, not tagged) because the closure struct's field type for a
captured concrete `Int` is `i64`, not a generic slot; UNIFORM vs. NATURAL
(§3) is a per-slot classification, not a per-data-structure one; a closure
struct can and does mix both kinds of field depending on each free
variable's own type.

---

## 5. Trampoline double-tagging (4n+3)

**Governing source:** the inline doc comment at `lib/tir/llvm_emit.ml`'s
`task_await_unwrap` case (search for "task_await_unwrap"; the comment above
the two conditional untag sequences states this mechanism and governs it; if
that comment and this section disagree at any point, the comment wins).
**History:** commit `291f6b5f` ("fix(codegen): double-untag i64 results in
task_await_unwrap").

`task_spawn`/`task_await_unwrap` hand a task's result through
`march_task_await_value`, which returns the *already-tagged* LLVM return
value (`llvm_ret`) stashed in `task[3]` by the spawn trampoline. For an
`i64`-typed task result, `llvm_ret` is itself `(2n+1)` (the function's normal
tagged-scalar return, §2); the trampoline stores that value into a `ptr`
slot, tagging it *again*: `((2n+1) << 1) | 1 = 4n+3`. One `coerce ptr→i64`
undoes exactly one tag layer, leaving `2n+1`, still tagged, not `n`. The fix
adds a **second** conditional untag (`emit_untag_scalar`) specifically for
the `i64`-result case; the `ptr`-result case needs only one, because a heap
address is even after one `ashr` and `inttoptr` restores it correctly without
a second pass.

**Claim 7: verified (IR).** `task_await_unwrap` on an `Int`-returning task
compiles to **two** full conditional-untag sequences chained:

```llvm
%tv11 = call ptr @march_task_await_value(ptr %ld9)
%cv12 = ptrtoint ptr %tv11 to i64
%cv13 = and i64 %cv12, 1
%cv15 = icmp ne i64 %cv13, 0
%cv14 = ashr i64 %cv12, 1
%cv16 = select i1 %cv15, i64 %cv14, i64 %cv12    ; first untag: 4n+3 -> 2n+1
%cv17 = and i64 %cv16, 1
%cv19 = icmp ne i64 %cv17, 0
%cv18 = ashr i64 %cv16, 1
%r20  = select i1 %cv19, i64 %cv18, i64 %cv16    ; second untag: 2n+1 -> n
```

**Claim 8: verified (behavior).** `task_spawn(fn _ -> 41 + 1)` awaited and
printed yields `42`, not `84` or a scheduler-count-skewed value, confirming
the double-untag is not just present but correct. (Probe:
`/tmp/w4-kapitsa-probe3-task.march`; transcript items 8–9.)

---

## 6. Atom hashing: `bit63 == bit62`

**Governing text:** `lib/tir/llvm_ctx.ml`'s `atom_hash` doc comment.

Atoms (`:foo`) are interned as an FNV-1a 64-bit hash of their name
(`fnv1a_64`, an exact mirror of the C runtime's hash), then
forced so **bit 63 equals bit 62** before use. Atoms are `i64` immediates
that may flow through a GENERIC (`ptr`) slot exactly like any other scalar
(§2/§3), where they are tag-encoded `(n<<1)|1` and later decoded with an
**arithmetic** `ashr`. That roundtrip is lossless only when the value is
effectively a sign-extended 63-bit integer, i.e. `bit63 == bit62`. A raw
64-bit hash without that property is corrupted on extract (the doc comment
cites `:put` / `:post` breaking Router method matching as the historical
symptom). Forcing `bit63 := bit62` preserves 63 bits of entropy while making
every atom safe for generic-slot transit; both atom-emission sites (literal
atoms and switch-arm tags) must go through this one function.

**Claim 9: verified (IR + arithmetic).** `match a do :put -> ... :post ->
... end` embeds the interned hash constants directly as `switch` operands:

```llvm
switch i64 878176697232756039, label %case_default4 [
    i64 -579996672871248402, label %case_br5
    i64 878176697232756039, label %case_br6
```

Checked both values bit-by-bit: `878176697232756039` has bit63=0, bit62=0;
`-579996672871248402` has bit63=1, bit62=1; both satisfy the invariant.
Simulating the tag/untag roundtrip (`((h<<1)|1)` truncated to 64 bits, then
arithmetic `>>1`) on both values recovers the original hash exactly, in both
the positive and negative case. (Probe: `/tmp/w4-kapitsa-probe5-atom.march`;
transcript item 10; roundtrip computed alongside it.)

**Claim 10: verified (behavior).** `classify(:post)` (matched against
`:put -> 1`, `:post -> 2`) compiles, runs, and prints `2`. (Transcript item
11.)

---

## 7. Niche and newtype representation

**Governing text:** `lib/tir/repr.ml` (the `repr` type and `repr_of_ty`/
`niche_payload_ok`/`payload_needs_tag`), consulted from `llvm_ctx.ml`'s
`type_defs`-carrying fields and `llvm_emit.ml`'s `EAlloc`/`emit_case`/
`ensure_adt_eq_fn` (the "repr-audit" infrastructure, `MARCH_REPR_AUDIT=1`, added in
`f0fe40cc`).

Three representations a monomorphic variant type can take, decided purely
from its shape (`Repr.repr`):

- **`Boxed`**, the general case: a heap cell with the normal RC header +
  tag, one variant among ≥2 non-degenerate ones.
- **`Newtype of ty`**: exactly one variant with exactly one field: the value
  *is* its payload, no wrapper cell at all (except float payloads, which stay
  boxed; float bits can't be safely tagged).
- **`Niche of { payload; tagged }`**, the Option-shape special case: exactly
  one nullary constructor and one single-field constructor (either order).
  `None` is the raw pointer value `0`; `Some(x)` is `x` itself (tagged via
  §2's scheme when the payload is a scalar, per `payload_needs_tag`).
  `niche_payload_ok` is the soundness gate: a payload type is safe for the
  raw-`0` niche only if it can never itself produce a `0` bit pattern in that
  slot (Int/Bool: always tagged-odd; String/heap pointers: `march_alloc`
  never returns null; nested niche/Float/Unit/`TVar`: rejected as unsafe,
  conservatively boxed).

This is what makes `Option(Int)`/`Option(String)`/etc. essentially free:
`None` has no cost (no allocation, a null check) and `Some` has no cost
beyond the underlying tag.

**Claim 11: verified (IR).** `match o do None -> 0 | Some(v) -> v end`
against a runtime-derived `Option(Int)` dispatches on a **null check**, no
tag load, no heap dereference for the `None` arm:

```llvm
%is_null3 = icmp eq ptr %ld1, null
br i1 %is_null3, label %niche_none2, label %niche_some3
niche_some3:
  %niche_raw7 = ptrtoint ptr %ld1 to i64
  %niche_unt8 = ashr i64 %niche_raw7, 1        ; unconditional: payload provably tagged
```

matching `emit_untag_known_scalar`'s unconditional-ashr shape exactly (no
`and`/`icmp`/`select`; the niche infrastructure already proved this slot contains a
tagged scalar, so the general conditional dance in §2 is unnecessary here).
(Probe: `/tmp/w4-kapitsa-probe4-niche.march`.)

**Claim 12: verified (behavior).** The same probe, compiled and run,
prints the correct payload for the `Some` arm actually taken. (Transcript
item 12–13.)

---

## 8. The shallow-free RC contract (record update)

**Governing text:** `runtime/march_extras.c`'s `march_record_update_dyn` doc
comment; contrasted with `march_record_field_dyn` immediately above it in the
same file.

A record update (`{ r with f: v, ... }`) on a **statically-known** shape
(`llvm_emit.ml`'s `EUpdate`, non-erased branch) allocates a new cell of the
same field count, copies every field from the base, then overwrites the
named ones: an ordinary NATURAL-repr copy, one allocation.

On a **type-erased** base (no static field list; the value arrived through
`record_get`/`record_put`/`record_from_list`, or crossed a generic boundary),
`llvm_emit.ml` cannot compute field offsets, so it calls
`march_record_update_dyn` (the by-name, shape-registry-aware runtime path;
this is the **B5 fix site**, see §9). Its RC contract, from the doc comment:
one allocation; each **untouched field is copied with `rec_field_copy`**,
which, like `march_record_put`'s established convention, takes a `+1`
reference on any heap-pointer child field being copied forward (a *shallow*
dup: the child cell itself is not deep-copied, only its reference count is
bumped, since the new record now retains an independent reference to the same
child). Each **updated field** takes ownership of the caller-supplied new
value directly (no incref: the caller already transferred it in). Update
names are resolved against the shape registry **before** any refcount
mutation begins ("resolve every name FIRST — fail loudly before touching
refcounts", per the C comment): a missing field name panics before any
`rec_field_copy` has run, so a bad update can never leave a partially-mutated
record's RC in an inconsistent state. Values arrive in **UNIFORM**
representation (scalars low-bit tagged) regardless of the base's field
kinds, exactly matching `march_record_put`'s calling convention; this is
intentional: NATURAL representation is ambiguous for a type-erased value (an
even `Int` ≥ 4096 shares its exact bit pattern with a plausible heap pointer, so a
plausible-heap sniff would wrongly `incrc`/dereference the integer; this is
exactly the `record_put`-large-even-int regression, §9).

**Claim 13: verified (IR).** `{ built with x: built.x + 100 }` on a
`record_from_list`-erased base compiles to a `march_record_update_dyn` call
with a value argument that is tagged (kind byte `105 = 'i'`):

```llvm
%ru69 = call ptr (ptr, i64, ...) @march_record_update_dyn(ptr %ld64, i64 1, ptr @.str4, i64 1, ptr %cv68, i64 105)
```

**Claim 14: verified (behavior).** The same probe, compiled and run,
produces the arithmetically correct sum with no crash and no memory
corruption; this exercises exactly the erased-update path the B5 fix
guards. (Probe: `/tmp/w4-kapitsa-probe7-update.march`; transcript items
14–15.) The pinned regression `test_compiled_record_put_large_even_int` in
`test/test_stdlib_suite.ml` covers the large-even-int + 20k-iteration case
this doc's probe does not re-run.

---

## History: bugs this contract would have prevented

One line per bug with a root cause that is a violation of a rule stated above,
with the fixing commit:

| Bug | Rule violated | Fix commit |
|---|---|---|
| **B5**: `EUpdate` on a type-erased record allocated a 0-field cell then wrote fields past it (OOB) | §8: erased updates must route through the shape-registry-aware runtime path, never a static field-count allocation | `0d1a829e` |
| **B9**: `march_`-prefixed runtime-extern-as-value check was off-by-one (6 vs 7 chars), making the arm dead and falling through to a 0-arg extern call | not a repr rule per se, but the same "single source of truth" discipline this doc follows (`Tir_names`); included as the namespace-collision sibling of the repr bugs | `cd0770d9`, regression-hardened in `5de438e8`/`e2d31a9f` |
| **B11**: REPL closure wrapper missed the uniform ptr-ABI fix, so a REPL closure returning a concrete `Int` came back halved/garbled on odd results | §4: every apply/dispatch path (including REPL wrappers) MUST return through the generic-ptr ABI, not a shortcut concrete return | `b32d8569` (sibling `3af54ede`) |
| **`task_await` double-tag**: `i64`-valued parallel task results (psum/preduce/par_fib) came back as `2×correct + N_workers` | §5: the trampoline's `task[3]` slot is *doubly* tagged for `i64` results and needs two conditional untags, not one | `291f6b5f` |
| **Cross-module/erased Option repr drift**: a boxed `None` (non-null) read by niche-matching code as `Some`, and a boxed `Some` cell read by niche code as the payload itself, for `Option(TVar)` crossing `record_get`/`alist_get`/generic helpers | §7: erased (`TVar`) Option payloads must stay NICHE at every commitment site, never fall back to `Boxed` inconsistently across sites | `f0fe40cc` (adds `MARCH_REPR_AUDIT`, diagnoses both drifts), unified further in `fbdadce4` |
| **`record_put` large-even-int SIGSEGV**: a NATURAL-repr even `Int` ≥ 4096 passed to `record_put` was sniffed as a heap pointer and dereferenced | §3/§8: type-erased record field writes must use UNIFORM (tagged) representation, never a "plausible heap pointer" runtime sniff over NATURAL bits | `b439d0f0` |

---

## Verification transcript (numbered, maps to Claims 1–14 above)

All probes compiled against HEAD `1b0bd91b` with
`./_build/default/bin/main.exe`, output always redirected (never piped).
Probe sources under `/tmp/w4-kapitsa-*.march`.

1. `--emit-llvm` on `probe1-tuple.march` (`(n+40, n+1)` destructured) →
   exit 0; IR shows the 4-instruction `and`/`icmp`/`ashr`/`select` untag
   (Claim 2).
2. `--compile` + run `probe1-tuple` → exit 0, prints `43` (Claim 3).
3. `--emit-llvm` on `probe1-tuple.march` again, allocation site → `store ptr`
   of tagged values into a 32-byte cell (Claim 4, Probe A).
4. `--emit-llvm` on `probe2-record.march` (`mk_point(n+40, n+1)`) → exit 0;
   allocation site shows `store i64` untagged into a 32-byte cell (Claim 5,
   Probe B).
5. `--compile` + run `probe2-record` → exit 0, prints `43`.
6. (same run as 5, folded into Claim 5's "both probes run correctly.")
7. `--emit-llvm` + `--compile` + run `probe6-closure.march`
   (`make_adder(5)(37)`) → exit 0 each step; IR shows the 2-field closure
   struct, `$fv1` NATURAL load, apply-wrapper `ptr` return + full untag at
   the call site; run prints `42` (Claim 6).
8. `--emit-llvm` on `probe3-task.march` (`task_spawn`/`task_await_unwrap` on
   `41+1`) → exit 0; IR shows two chained conditional-untag sequences
   (Claim 7).
9. `--compile` + run `probe3-task` → exit 0, prints `42` (not `84`) (Claim 8).
10. `--emit-llvm` on `probe5-atom.march` (`match :post do :put/:post/_`) →
    exit 0; switch operands `878176697232756039` / `-579996672871248402`
    checked bit-by-bit (`python3`) for `bit63==bit62`, both hold; tag/untag
    roundtrip simulated arithmetically on both, both lossless (Claim 9).
11. `--compile` + run `probe5-atom` → exit 0, prints `2` (Claim 10).
12. `--emit-llvm` on `probe4-niche.march` (`Option(Int)` runtime-derived) →
    exit 0; IR shows `icmp eq ptr %ld1, null` dispatch + unconditional
    `ashr` on the `Some` arm (Claim 11).
13. `--compile` + run `probe4-niche` → exit 0, prints `2` (Claim 12).
14. `--emit-llvm` on `probe7-update.march` (`record_from_list` +
    `{ built with x: ... }`) → exit 0; IR shows
    `@march_record_update_dyn` called with kind byte `105` ('i', tagged
    UNIFORM value) (Claim 13).
15. `--compile` + run `probe7-update` → exit 0, prints `103` (Claim 14).

Claims stated without a probe number (header layout arithmetic, the tag law's
exact instruction shapes, the closure struct field-index convention, the RC
shallow-copy contract's prose) are cited to their governing module/doc
comment/commit directly, per the plan's citation rule, rather than
re-executed independently; the probes above exercise the code paths that
implement them.
