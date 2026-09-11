`[P2]` - [ ] **Type kinds: one per-type table, computed once and threaded.**

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
