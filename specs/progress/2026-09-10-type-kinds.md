`[P2]` - [x] **Type kinds: one per-type table, computed once and threaded.**

Filed 2026-09-10. Design: `specs/2026-09-10-type-kinds-design.md`.

Replace the per-type predicates in `lib/tir/rc_types.ml` and `lib/tir/repr.ml`
(~230 call sites across `needs_rc`, `borrow_eligible`, `repr_of_ty`,
`is_niche_shaped`, `niche_payload_ok`, `payload_needs_tag`,
`niche_repr_of_concrete`, `llvm_ty`) with one `kind` record per monomorphic
type: layout, repr, needs_rc/borrowable, niche_ok/needs_tag, plus the deep
crossing facts (closure_free / float_free / linear_free, computed but unread
until items 3 and 5).

**The real work is removing global state, not deduplicating predicates.**
Milestone 3 (`c0275445`) gave `repr.ml` four process-global mutable cells and
six lifecycle entry points driven from five call sites. `_forced_off` is a
**latch that is never cleared** and that `clear_unboxed_types` does not reset,
so any process building one `~repl:true` context has unboxing off for life —
including `test/test_codegen.ml:2357`, in the same process as the
unboxed-aggregate cases. Same class as the TRMC fresh-name-counter bug that
made TIR depend on run order. `repr.ml`'s module doc still claims it is "a pure
function of the MONOMORPHIC type ... with no threading of state"; that is false
and is corrected in Phase 1 regardless of what else lands.

Strictly behaviour-preserving: no representation changes, no diagnostics, no
surface syntax. Four oracle-gated phases (prove the oracle RED first, private
`HOME`); Phase 3 reorders initialisation so it also needs the LSP suite,
`test_jit`, and a real `forge build`. Preserve verbatim: the `needs_rc` vs
`borrow_eligible` four-constructor divergence and its ~90 lines of fix-history
documentation, plus its pinning test.

Blocks item 5 (unboxed Float layout). Origin: item 2 of the OxCaml review
(`specs/2026-09-03-allocation-contracts-design.md`).

---

**Landed 2026-09-11.** `lib/tir/kind.ml` (+ `.mli`) is the per-type table:
one `kind` record per monomorphic type — layout, repr (Boxed / Newtype /
Niche / Unboxed), `needs_rc`, `borrowable`, niche safety, LLVM spelling, and
the deep `closure_free` / `float_free` crossing facts (computed, unread) —
built once per module by `Contract_pipeline.run` right after Defun, handed to
Borrow, Perceus, Drop, Escape and Alloc_contract, rebound to the final type
list with `Kind.rebind`, and carried by `Llvm_ctx.ctx.k_table` into the
emitter.  Pass entry points take `?k_table` with a standalone default
(`Kind.of_module`), so tests, the LSP and the REPL/JIT keep calling them
directly.

**What went away.** `rc_types.ml` (its ~165-line fix-history module doc moved
verbatim into `kind.ml`); `repr.ml`'s four process-global mutable cells and six
registration entry points, including the never-cleared `_forced_off` latch
that made representation depend on in-process run order; the free
`Llvm_ctx.llvm_ty` / `llvm_field_ty` / `llvm_ret_ty` (now take the ctx; 75
call sites migrated).  `repr.ml` is a type re-export.  The REPL's "never
unbox" is now `Kind.build ~unboxing:false`, a per-table argument.

**Proof.** IR oracle (`scripts/ir-oracle.sh`, 262 programs, private `HOME`)
proven RED on a deliberate perturbation (skipping `Known_call`: 524 differing
lines) before any GREEN was trusted; IDENTICAL after Phase 1.4, batches
2a/2b/2c, Phase 3a, and Phases 3b+3c.  TIR snapshots (45) unmoved
throughout.  Phase-3 gate `scripts/run-tests.sh` over every suite but refinecheck (z3-only,
cannot observe a TIR change; its 706 cases passed on the merged base the same
day): exit 0, 11 suites, 3299 tests, 0 failures — 1021 / 280 / 615 (codegen:
604 + 12 `kind` − 2 moved `rc_types` + 1 latch test) / 879 / 61 / 24 / 361 / 5 /
36 / 10 / 7.  REPL smoke (`test/repl_smoke_test.sh`, private HOME): 48 pass /
6 fail, versus 47 / 7 for the INSTALLED pre-refactor 0.4.0 binary on the same
cases — the failures are an unconditional `[timing]` stderr line
(`lib/repl/repl.ml:350`) the smoke regexes do not expect, pre-existing and
unrelated.  Real project: `bastion_todos` (22 files) builds through the
worktree compiler via `forge build` and the binary runs; `by_chase` and
`blog_app` fail identically on the installed toolchain (missing dependency
modules), so they are project issues, not compiler ones.  Two new tests are the readable
proof the latch is gone: `unboxed_aggregates/"a REPL ctx does not latch
unboxing off"` (a `~repl:true` ctx built first, then a normal Vec3 emit still
declares `%ub.Vec3`) and `kind/"tables do not leak between modules"`.

**What the migration found.**
- Phase 3b, before `llvm_ty` was migrated, produced INVALID LLVM IR for every
  program with an unboxed aggregate (`insertvalue operand must be aggregate
  type`): the free `llvm_ty` still read the now-unpopulated registry ("ptr")
  while the rest of the emitter read the table (a struct) — exactly the
  encode/decode split the design warns about, caught by the test suite before
  the oracle ran.  There is no table-free spelling any more, by construction.
- `Llvm_toplevel.fn_declare_str` and one `repl_jit.ml` site have no ctx; both
  are JIT-only, where nothing is unboxed, so `Kind.empty`'s spelling is exactly
  the REPL ctx's.  Documented at both sites.
- `test_repr_multifield_is_boxed` asserted `Point(Int, Int)` is Boxed, which
  was only true because the old registry happened to be empty in that test;
  it now asks a table with unboxing off, preserving its pre-Milestone-3
  meaning.
- The two `is_closure_ty` functions were not duplicates (one tests a
  closure-struct name, the other `TFn | TVar`); renamed `is_clo_struct_ty` and
  `is_indirect_callable_ty`, not unified.
- `specs/features/compiler-pipeline.md` still says TRMC is off by default; it
  is on since 2026-09-09.  Out of scope here; noted for whoever touches that
  table next.
