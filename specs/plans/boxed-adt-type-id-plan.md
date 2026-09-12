# Plan: give boxed ADT cells a runtime type id

**Closes:** `specs/todos/2026-08-05-boxed-adt-type-id.md` (residuals 1 and 5; see
"What this does NOT close" for why 2, 3 and 4 stay open).
**Status:** landed 2026-09-11 (`specs/progress/2026-09-11-boxed-adt-type-id.md`). Decision graph goal 1892.
**Date:** 2026-09-11

## The gap, in one paragraph

A boxed constructor cell is `{ rc:i64; tag:i32; pad:i32 }` + fields. `tag` is the
constructor index, numbered per type from 0, so `IOList.Str("x")` and a user
`B("x")` are byte-identical. Every renderer that has a STATIC type
(`to_string`, `println`, `~H`) was fixed on 2026-09-08 by passing a
compile-time descriptor id (`lib/tir/llvm_ctor_desc.ml` +
`march_ctor_table_ensure`). What remains is the genuinely erased slot: a value
that reaches a `~H` hole or `to_string` through a `TVar`, which mono does not
specialise. Today that arm stringifies for safety, so a real `IOList` renders
as `#<tag:2>` (pinned as `poly_iolist` in
`test/native/h_sigil_adt_interp.expected`), and a generic field inside a
described type (`Cons(a, ...)` at `List(Shape)`) renders its elements through
the untyped renderer (residual 5).

## What the survey found (constraints the design must respect)

1. **`pad` is already multiplexed**, not free. Three users, all on cells that
   are NOT user ADTs but share `tag == 0` with a ctor-0 ADT cell:
   - record shape id, `>= 1`, via `march_record_set_shape`
     (`runtime/march_extras.c:2189`); `rec_shape_of` rejects `id <= 0`.
   - closure flag `MARCH_CLO_ARG0_BORROWED = 1` (`runtime/march_runtime.h:135`,
     emitted by `lib/tir/clo_flags.ml`).
   - SIMD lane kind `0..4`, only under `MARCH_SIMD_TAG`.
   So ADT ids must be **disjoint from every positive small integer**: use
   **negative** values. `rec_shape_of`'s existing `id <= 0` guard then makes an
   ADT cell handed to a record builtin read as "no metadata", which is today's
   behaviour.
2. **Every header store in the emitter goes through two choke points**:
   `Llvm_data.emit_store_tag` (`lib/tir/llvm_data.ml:25`, called by
   `emit_heap_alloc` and by every FBIP reuse / alloc-hole / stack-alloc restamp
   in `llvm_emit_alloc.ml`) and the unboxed-aggregate box in
   `Llvm_ctx.coerce` (`lib/tir/llvm_ctx.ml:751`). The closure-wrapper cells in
   `llvm_emit.ml:422/552/608` store tag 0 and are not ADTs; leave them.
3. **FBIP reuses a freed cell by ARITY, not by type** (`perceus_fbip.ml:37`).
   A `Cons` cell can be rebuilt as some other 2-field constructor. Every reuse
   path already calls `emit_store_tag` with the NEW constructor's tag, so
   stamping the id in the same helper covers reuse for free. Stack cells
   (`emit_stack_alloc`) zero the whole tag+pad word and then get
   `emit_store_tag`; same story.
4. **The runtime builds ADT cells in C without the emitter**: `make_cons`,
   `make_some_i64`, `make_ok`, `make_err`, tuples, HTTP headers, roughly
   24 + 14 + 61 sites across `march_runtime.c`, `march_extras.c`,
   `march_http.c`. Those cells will carry `pad == 0`. The design must treat
   `0` as "unknown, fall back to today's behaviour", never as a type.
5. **Two sites compare the whole 64-bit tag+pad word**:
   `((int64_t *)msg)[1] == MARCH_MIGRATE_TAG` at `march_runtime.c:3226` and
   `:4581`. `MARCH_MIGRATE_TAG` is `0x4D494752` on a malloc'd C struct, so a
   stamped cell can only collide if `tag == 0x4D494752` with `pad == 0`;
   ordinary tags are `< MARCH_ORDINARY_CTOR_TAG_LIMIT = 0x01000000`. Safe, but
   assert it in a runtime self-test rather than assume it.
6. **Cross-heap copy is fine**: `copy_value` (`march_message.c:229`)
   `memcpy`s the whole cell including the header, so ids survive actor sends.
   The GC (`march_gc.h`) and `alloc_meta` never read `pad`. Equality
   (`llvm_eq.ml:410`) and impl dispatch (`llvm_dispatch.ml:66`) load `i32` at
   offset 8, so a nonzero pad changes nothing for them.
7. **The descriptor table is per compilation unit with a runtime BASE**
   (`march_ctor_table_ensure` appends and returns the base). A header id
   stamped at allocation must be a **compile-time constant** or every
   allocation pays a load + add on top of the store. So the id cannot be
   `base + local_id`.
8. `Llvm_ctor_desc.id_for` deliberately emits nothing at sites that answer
   `None`, because forcing the descriptor put ~13KB of rodata into every
   binary that called `to_string` on a non-primitive. Eager registration must
   be gated on the unit actually containing an erased render site.
9. The todo's claim that a header id "would close 1, 2, 3 and 5" is wrong for
   2 and 3. A niche `Some(x)` IS `x` and a newtype IS its payload: **there is
   no cell to stamp**. Stamping the payload's cell with the payload's id makes
   the renderer print the payload's constructor, which is the same wrong
   answer `describable` refuses today. Correct the todo when filing progress.

## Design

### Id scheme

`type_id = -(1 + (fnv1a32(type_name) & 0x3FFF_FFFF))`, so the id is always in
`[-2^30, -1]`.

- **Constant at every allocation** (constraint 7): no base, no load.
- **Stable across compilation units** (native binary, `--compile-so` hot-reload
  patches, REPL/JIT fragments) because it is a pure function of the name.
- **Disjoint from every existing `pad` user** (constraint 1) by sign.
- `type_name` is exactly the string `Llvm_ctor_desc.build_desc` writes on the
  `T` line (the first-wins short name `Llvm_toplevel.build_ctor_info` keys
  `ctor_info` on), so the runtime can recompute the hash from the descriptor
  it already parses and needs no new wire format.
- The C runtime can name the prelude types it builds itself
  (`MARCH_TYPE_ID_LIST`, `_IOLIST`, `_OPTION`, `_RESULT`) with the same
  function at init. Phase 4 uses this; phases 1 to 3 do not depend on it.

**Collisions.** 30 bits over a few hundred names gives a per-process collision
probability around 1e-4. A collision must never print a wrong constructor
(the failure mode `describable` calls "worse than the bug being fixed"), so:

- `march_ctor_table_ensure` builds an `id -> type row` map; on a second
  distinct name for the same id it marks the id AMBIGUOUS, and the renderer
  falls back to `#<tag:N>` for it. Wrong answers are impossible; the cost of a
  collision is one type reverting to today's output.
- `Llvm_ctor_desc.assign_ids` checks the same thing statically within one
  unit and emits a warning naming both types. Deterministic, so a test can
  pin it with two crafted names.

### Emitter

- `Llvm_data.emit_store_tag ctx ptr tag` becomes
  `emit_store_hdr ctx ptr ~tag ~type_id` and emits **two `i32` stores**
  (offset 8 and 12) rather than one packed `i64`: endian-agnostic, and LLVM's
  store merging folds adjacent constant stores at `--opt 1+`. Verify the fold
  in Phase 1 (`--emit-llvm` writes `<source>.ll`, read the FILE, then
  `opt -O2` and grep for a single `store i64` per allocation); if it does not
  fold, switch to the packed `i64` form and document the little-endian
  assumption next to `march_hdr`.
- `emit_heap_alloc ctx tag n` gains the id; every caller in
  `llvm_emit_alloc.ml` has a `ctor` string in scope from which the type name
  is `String.sub` up to the last `.` (the same split `emit_reuse_ctor` already
  does at line 518). Records pass id 0 (`emit_set_shape` overwrites pad with
  the positive shape id; keep records on that scheme).
- `Llvm_ctx.coerce`'s unboxed-aggregate box (`llvm_ctx.ml:751`) has `tname`
  in hand; stamp it too, or an `Unboxed` value crossing into an erased slot
  reads as unknown exactly where the erased path needs it.
- A single `Llvm_ctx.type_id_of_name : string -> int` owns the hash so the
  emitter and `Llvm_ctor_desc` cannot drift; the C side gets the same function
  as `march_type_id_of_name` with a shared test vector (one known
  name → id pair asserted in both an alcotest case and a runtime self-test).

### Runtime

- `runtime/march_runtime.h`: document the new pad convention next to
  `march_hdr`; `static inline int32_t march_hdr_type_id(void *v)` returns
  `pad < 0 ? pad : 0`.
- `march_extras.c`: `march_ctor_table_ensure` indexes rows by hashed id
  (with the ambiguity rule above). New `march_value_to_string_dyn(v)`: if
  `march_hdr_type_id(v)` resolves to a row, render through the existing
  `ctor_render`; else today's `march_value_to_string`. Inside `ctor_render`,
  a `'p'` (generic) slot holding a heap pointer with a resolvable id renders
  through the table too. That is what closes residual 5.
- `march_html_auto_escape`: replace the partial `tag > 2` guard with an exact
  decision: flatten iff `march_hdr_type_id(v) == MARCH_TYPE_ID_IOLIST`; for
  `id == 0` (C-built or pre-stamp cell) keep the existing partial guard
  unchanged; for any other id, render via `march_value_to_string_dyn` and
  escape as a String. `march_html_auto_escape` is called only with IOLists and
  Strings from the static path today, so this arm only changes behaviour for
  the new dynamic route.
- Eager registration: the descriptor must be registered BEFORE the first
  erased render, and the runtime cannot find it on its own. Emit a
  `march_ctor_table_ensure` call in `@main` (`llvm_toplevel.ml`, next to the
  hot-reload sizing IR at line 853) and in each REPL fragment finalizer, gated
  on "this unit contains at least one erased render site" so binaries that
  never need it keep paying nothing (constraint 8).
- WASM: `march_extras.c` is not built for WASM (that is what the
  `shape_meta` gate is for). The stores are harmless there; every new runtime
  entry point stays behind the same gate as `id_for`.

### Emitter dispatch changes (the payoff)

- `llvm_emit_html.ml:85`, the `TVar` arm of `emit_html_auto_escape`: route to
  a new `march_html_auto_escape_dyn`, which is the exact-check version above.
  The security property (never emit a non-IOList field raw) is now enforced by
  identity, not by refusing.
- `llvm_emit_html.ml:33` and the `to_string` path in `llvm_emit_builtins`:
  when `id_for` answers `None` for a `TVar`, call `march_value_to_string_dyn`
  instead of `march_value_to_string`.
- Interpreter: no change; it has always had the type.

## What this does NOT close

- **Residual 2 (niche `Option`) and 3 (newtype)**: no cell, nothing to stamp.
  Update the todo's narrowing note so the next reader does not expect this
  mechanism to reach them.
- **Residual 4 (anonymous records / tuples)**: no declared name to hash.
  Records already carry a shape id and could be rendered by shape in a
  follow-up; tuples cannot.
- **C-built cells** carry `0` until Phase 4 stamps the prelude builders. Until
  then a `Cons` produced by `string_split` reaching an erased slot renders as
  it does today, which is correct-by-fallback.

## Phases and gates

### Phase 0: RED witnesses first

1. `test/native/h_sigil_adt_interp.expected`: change `poly_tag1`, `poly_tag2`
   and `poly_iolist` to the interpreter's rendering (the interpreter already
   prints them correctly; the golden runs both). This is the todo's original
   witness. Do NOT touch the `record`, `tuple`, `some`, `none` lines.
2. New native golden `test/native/erased_to_string_type_id.march`: a
   `List(Shape)` nested in a described type, rendered by `to_string` (residual
   5), plus a value printed through the `Bx(Cons(fn x -> to_string(x), Nil))`
   pattern so the TVar path is exercised. Remember `(source_tree ../stdlib)`
   in the dune rule or the fixture emits invalid IR silently.
3. A security-direction witness: the SAME closure box fed a tag-1 user ADT
   whose field is `"<script>"` must still escape. Already pinned by lines in
   the existing golden; keep them and make sure they stay green through every
   phase, because the new dynamic route is exactly where an XSS would return.
4. Runtime self-test (`march_sso_selftest` style): `march_type_id_of_name`
   vector, negativity, and the `MARCH_MIGRATE_TAG` non-overlap invariant.

Run the goldens and confirm all of 1 and 2 fail for the expected reason
(`#<tag:N>`), not for a compile error.

### Phase 1: stamp

Emitter choke points + `march_hdr_type_id` + the self-test. Gates:

- `scripts/ir-oracle.sh check` must go **RED** on essentially every program
  (every boxed allocation changed). That is the proof the stamp reached the
  cells. Re-baseline afterwards, under a private `HOME`.
- Benchmarks, compiled, `--opt 2`, same box, A/B against a compiler built at
  the base commit (an absolute-ms baseline is not a detector):
  `bench/binary_trees.march` (allocation-heavy) and
  `bench/tree_transform.march` (FBIP reuse). Threshold: no A/B delta beyond
  run-to-run noise; check `uptime` first. Expected: zero delta once the two
  stores fold into one `i64` store.
- Full `scripts/run-tests.sh` green; `test_codegen.ml`'s preamble golden may
  need its expected text updated if it contains a header store.
- No behaviour change is visible yet; Phase 0's witnesses stay RED.

### Phase 2: consumers

Runtime table indexing + `_dyn` entry points + eager registration + the two
emitter dispatch changes. Gates: Phase 0 witnesses GREEN; the security lines
unchanged; `test/native/h_sigil_adt_interp.expected` diff is exactly the
three `poly_*` lines; REPL smoke (`repl_smoke_test.sh`, private HOME, baseline
48/6) shows ids agree across fragments (a fragment-1 value rendered in
fragment 2 through an erased slot); `--compile-so` patch renders a
host-allocated value.

### Phase 3: close the books

`git mv` the todo to `specs/progress/2026-09-11-boxed-adt-type-id.md`, with
the corrected residual list (2, 3, 4 stay open, file them as their own todos
if they are worth keeping). CHANGELOG `### Fixed` bullet. Update
`specs/impl/` wherever `march_hdr` layout is documented (`scripts/check-docs.sh`
guards pointers, not layout prose, so grep for `pad` there by hand).
Refresh the IR oracle baseline.

### Phase 4 (optional follow-up, separate PR)

Stamp the C builders (`make_cons`, `make_some_i64`, `make_ok`, `make_err`,
tuples, HTTP header pairs) with the prelude ids so runtime-built lists and
results carry identity. About 100 sites; do it by giving each `make_*` helper
the id rather than touching call sites.

## Risks called out in advance

- **A wrong constructor is worse than a placeholder.** Every dynamic render
  must resolve an id to exactly one row or fall back. The ambiguity rule and
  the `id == 0` fallback are load-bearing; test both directions (a stamped
  cell renders by name; an unstamped or ambiguous one renders `#<tag:N>`).
- **Reuse restamp.** If any reuse path bypasses `emit_store_tag` and stores
  the tag directly, a reused cell keeps its OLD type's id. Grep for
  `getelementptr i8, ptr %s, i64 8` after Phase 1 and account for every hit
  (today: `llvm_data.ml:21,75`, `llvm_ctx.ml:753`, the three closure wrappers
  in `llvm_emit.ml`, and the read-only sites in `llvm_eq.ml` /
  `llvm_dispatch.ml`).
- **Stale `_build` runtime.** A targeted `dune build bin/main.exe` does not
  restage `runtime/*.c`; build a target with a runtime dep or the C half of
  this change is simply not in the binary being tested.
- **`~/.cache/march` and the IR oracle**: run under a private `HOME`, prove
  RED before trusting GREEN.
