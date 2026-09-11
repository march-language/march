# Type kinds — design

## Scope

Replace the per-type predicates scattered across `lib/tir/rc_types.ml` and
`lib/tir/repr.ml`, and the process-global mutable registry that `repr.ml`
acquired with the unboxed-aggregate work, with **one table computed once per
module and threaded explicitly**: a `kind` record per monomorphic type
carrying its layout, its representation, the reference-counting answers, and
the deep "crossing" facts.

Strictly behaviour-preserving. No representation decision changes, no
diagnostic changes, no new TIR node. The deliverable is that every question of
the form *"what can values of this type do?"* has exactly one answer computed
in exactly one place, and that answer is a value rather than process state.

This is item 2 of the OxCaml review (`specs/2026-09-03-allocation-contracts-design.md`,
Roadmap context). Item 5 (unboxed Float layout) depends on it.

## Why now

Two things changed since the review, and both make this larger and more
load-bearing than the original sketch.

### 1. The scatter grew

Consumers outside the defining module, measured 2026-09-10 (2026-09-03 figures
in parentheses where they differ):

| Predicate | Call sites |
|---|---|
| `Rc_types.needs_rc` | 61 (was 47) |
| `Rc_types.borrow_eligible` | 9 |
| `Repr.repr_of_ty` | 40 (was 31) |
| `Repr.is_niche_shaped` | 23 (was 20) |
| `Repr.niche_payload_ok` | 13 |
| `Repr.payload_needs_tag` | 12 |
| `Repr.niche_repr_of_concrete` | 11 |
| `Repr.is_actor_struct_type` | 5 |
| `Llvm_ctx.llvm_ty` | 55 |
| `Llvm_ctx.llvm_param_ty` | 8 |

Most take `type_defs` and an optional `collision_set` as arguments, so every
call site re-derives the same facts and each one can pass a *different*
`collision_set` (the parameter defaults to an empty table, which silently means
"nothing collides"). `repr.ml` grew from ~200 to 431 lines.

There are also two unrelated functions both named `is_closure_ty`, in
`lib/tir/borrow.ml:238` and `lib/tir/cprop.ml:75`, that answer differently: one
tests a closure-struct *name*, the other tests `TFn | TVar`.

### 2. `repr.ml` is no longer a pure function of the type

Its module doc still opens:

> "A pure function of the MONOMORPHIC type: after monomorphization every type
> is concrete, so representation can be decided per type with no threading of
> state."

That is now false. Milestone 3 (`c0275445`, unboxed scalar-only single-ctor
variants) added four process-global mutable cells and six lifecycle entry
points:

- `_unboxed`, `_unboxed_by_llvm`, `_registered_from` — the registry and its
  provenance;
- `_forced_off : bool ref` — a **process-wide latch**;
- `set_unboxed_types`, `ensure_unboxed_types`, `clear_unboxed_types`,
  `rebind_registration`, `force_disable`, plus a `MARCH_NO_UNBOX` env override.

Registration is driven from five places that must agree:
`Contract_pipeline.run` (sets, then `rebind_registration` before emit),
`Perceus`, `Escape` (both `ensure`), `Llvm_ctx.make_ctx` (`ensure`, or
`force_disable` + `set ~enabled:false` when `~repl:true`), and `Repl_jit`
(`force_disable`).

**The latch is never cleared, and the reset helper does not cover it.**
`clear_unboxed_types` resets `_unboxed`, `_unboxed_by_llvm` and
`_registered_from`, but not `_forced_off`; its own comment records the intent
("a process either drives the REPL or it does not"). Any process that
constructs one `~repl:true` context has unboxing disabled for its whole
remaining life. `test/test_codegen.ml:2357` does exactly that, in the same
process as the unboxed-aggregate cases registered around line 14800, so
behaviour there depends on alcotest registration order. Today the order is
favourable; nothing enforces that, and a REPL case registered earlier would
change what the later cases actually exercise.

This repo has already paid for this failure mode once: a global fresh-name
counter made TIR depend on run order and was invisible twice over
(`specs/progress/` TRMC counter determinism). Global mutable state in a
pipeline stage is the disease; a threaded value is the cure. Doing that is
most of this refactor's real work, and it is why the refactor should land
before anything else touches representation.

## The table

New module `lib/tir/kind.ml`. It depends on `Tir`, `Tir_names`,
`Collision_set`; every current consumer may depend on it.

```ocaml
type layout =
  | Imm                        (* i64 register: Int, Bool, Unit, Atom, tagged newtype *)
  | Flt                        (* double register; boxes at an erased slot *)
  | Vec  of int                (* SIMD vector; int is the runtime kind tag *)
  | Agg  of string             (* inline LLVM struct VALUE; the "%ub.T" name *)
  | Heap                       (* RC'd pointer: String, TPtr, boxed TCon, closure *)
  | Cell                       (* tuple/record: heap cell, RC reconciled per FIELD *)
  | Erased                     (* TVar: uniform slot, conservatively heap *)

type kind = {
  layout       : layout;
  repr         : Repr.repr;    (* Boxed | Newtype | Niche | Unboxed *)
  llvm_ty      : string;       (* the one spelling; llvm_ty/llvm_param_ty read it *)
  needs_rc     : bool;         (* Perceus's question *)
  borrowable   : bool;         (* Borrow's question — deliberately differs *)
  niche_ok     : bool;         (* never raw 0, so usable as a niche payload *)
  needs_tag    : bool;         (* scalar needing (v<<1)|1 in a ptr slot *)
  closure_free : bool;         (* DEEP: no TFn reachable through fields *)
  float_free   : bool;         (* DEEP: no TFloat reachable through fields *)
}

type table

val build :
  ?externs:Tir.extern_decl list ->
  ?unboxing:bool ->                    (* false = the old force_disable *)
  collision_set:(string, string list) Hashtbl.t ->
  Tir.type_def list -> table

val of_ty : table -> Tir.ty -> kind
val of_name : table -> string -> kind option    (* params-less TCon path *)
val unboxed_by_llvm : table -> string -> (string * string * Tir.ty list) option
```

`build` absorbs every input the current registration takes, so the exclusions
that `set_unboxed_types` documents — extern-crossing types, actor message
types, colliding short names, closure structs and actor state records — become
arms of one derivation rather than conditions re-tested at call sites.
`of_ty` is memoised per table.

### Crossing facts

`closure_free` and `float_free` are computed **deeply**, through constructor
arguments and record fields, with a visited set so recursive types terminate.
They are OxCaml's mode-crossing table in March's vocabulary: a `closure_free`
type can cross a `pmap` or `send` boundary without inspecting its contents; a
`float_free` type never needs a box at an erased slot.

There is deliberately no `linear_free`. Linearity is erased at lowering
(`lower_types.ml`: `TyLinear (_, t) -> lower_ty t`, "linearity tracked on
var") and lives on `Tir.var.v_lin`, not on `Tir.ty`, so a per-type answer
cannot be derived and a field carrying a constant `true` would be a lie with a
name. If item 4 (borrow regions) ever needs a per-type linearity fact, that is
the point at which a marker has to survive lowering, and the field gets added
then.

**No consumer reads the two fields in this refactor.** They are computed,
unit-tested against a fixture corpus, and left unread. They exist so that
items 3 and 5 have somewhere to ask, and so the module is named for what it
is. If that proves controversial in review, dropping them costs nothing else
in this design.

## Threading

`Contract_pipeline.run` already owns the post-lower pass sequence and already
drives registration twice. It becomes the table's owner: build once from
`tm_types` + `Collision_set.compute` + `tm_externs`, then pass it to each pass
that needs it. `Llvm_ctx.ctx` gains a `k_table` field; `make_ctx` takes the
table instead of registering into globals, and its `~repl:true` arm passes
`~unboxing:false` to `build` rather than latching a process flag.

The REPL and JIT build their own table with `~unboxing:false`. That is the
whole of what `force_disable` was for, expressed as an argument.

After migration, `repr.ml` keeps the `repr` type and the pure shape
classifiers; the four mutable cells and the six lifecycle functions are
deleted. `rc_types.ml` is deleted, its module documentation moved to `kind.ml`
verbatim — see Invariants.

## Invariants that must not move

1. **The `needs_rc` / `borrowable` divergence.** They disagree on exactly four
   constructors — `TFn` and bare `TVar` (rc true, borrow false), and `TTuple`
   and `TRecord` (rc true, borrow false as of the aggregate-ownership change;
   before it the aggregate rows were rc false / borrow true) — plus the
   `Repr.Unboxed` row where both are false. Every arm has its own fix history
   (the `Map.fold` crash, the `Gate.cast` RC-underflow use-after-free, the
   closure-FV ownership contract, the Toml pair-list corruption, the
   self-tail-recursive aggregate leak). `rc_types.ml` carries ~130 lines of
   documentation explaining why. **That documentation moves verbatim into
   `kind.ml`**, and its two pinning tests in `test_codegen.ml` ("rc_types"
   group: the truth table and the exact divergence set) move with it,
   retargeted at the table. A reviewer must be able to find the same warnings
   in the same words. The truth table is whatever `rc_types.ml` says on the
   day Phase 1 starts, not what this document says.
2. **Encode and decode stay in lock-step.** `is_niche_shaped` gates the EAlloc
   encode path and the `llvm_case` decode path; `niche_repr_of_concrete`
   independently re-derives the same classification for params-less `TCon`.
   Both must read the same table entry, which is the point, but the
   equivalence has to be proven per call site rather than assumed.
3. **Forced-Boxed exclusions.** Actor message types (foreign-message dispatch
   needs a runtime tag) and colliding short names (their globally-unique ctor
   tag must stay readable) are Boxed regardless of shape, in every one of the
   three places that currently re-test it.
4. **Unboxing exclusions.** Extern-crossing types stay Boxed: the C side was
   written against the boxed cell, and `needs_rc` is false for the aggregate,
   so an unboxed-then-boxed value would leak once per call.

## Migration

Four phases, each independently revertible, each oracle-gated.

- **Phase 0 — prove the instrument.** `scripts/ir-oracle.sh baseline`, then a
  deliberate perturbation (e.g. skip `Known_call`), confirm RED, restore,
  confirm GREEN. Two of the three oracle scripts have shipped broken, and one
  was certified "verified" while broken, so this is not optional. Run under a
  private `HOME`: `~/.cache/march` is shared across worktrees and its cached
  spans carry the populating worktree's absolute paths.
- **Phase 1 — add `Kind`, delegate to it.** `rc_types.ml` and `repr.ml`
  become thin wrappers over `Kind.of_ty`. No call site changes. Oracle green,
  TIR snapshots unmoved, full suite green.
- **Phase 2 — migrate call sites, one file per commit.** Largest consumers
  first (`llvm_ctx`, `llvm_emit*`, `perceus*`, `borrow`). Oracle green after
  each.
- **Phase 3 — thread the table, delete the globals.** `Contract_pipeline`
  builds it; `Llvm_ctx.ctx` carries it; the four mutable cells and six
  lifecycle functions go. This is the phase that changes *when* things are
  computed, so it gets its own oracle run plus a REPL/JIT smoke run
  (`repl_smoke_test.sh` under a private `HOME`, baseline 48/6).
- **Phase 4 — collapse the duplicates.** The two `is_closure_ty`, and any
  predicate the migration reveals as a third copy.

The oracle is blind to `lib/eval/` and `lsp/`, and sees neither match-arm order
nor module-initialisation order. Phase 3 reorders initialisation by
construction, so it additionally needs: the LSP suite, `test_jit`, and a
`forge build` of one real project.

## Testing

- The `rc_types` truth-table test, retargeted: all 11 `Tir.ty` constructors ×
  `needs_rc` / `borrowable`, with the four divergent arms called out by name.
- Representation classification over a fixture corpus covering each `repr`
  arm, both forced-Boxed exclusions, and each unboxing exclusion.
- Crossing facts: a closure in a record field, a float in a nested variant, a
  recursive type (terminates), a mutually recursive pair.
- **Determinism:** build the table twice from the same `type_defs` in one
  process and assert structural equality, and build it from two different
  modules in one process and assert neither sees the other's entries. This is
  the regression test for the class of bug Phase 3 removes.
- **Latch removal:** construct a REPL context and then a non-REPL one in the
  same process, and assert the second still unboxes. This fails before
  Phase 3 and passes after, which is the readable proof the latch is gone.
- Snapshots: `test/snapshots/` must not move in Phases 0-2. Phase 3 must not
  move them either; if it does, the diff is the review artifact and needs an
  explanation, not a regeneration.

## Non-goals

- No representation decision changes. In particular the finding from the
  allocation-contract work — that a nullary constructor is not uniformly free,
  since `List.Nil` in a variant with payload-carrying cases emits a real cell
  while an all-nullary enum does not — is **recorded** as a kind fact and
  **not** changed here.
- No surface syntax. Kinds are not written in signatures and produce no
  diagnostic. That is what would make this a type-system feature rather than a
  compiler consolidation, and it should wait until item 3 or 5 needs it.
- No unboxed Float layout (item 5), no portable-closure check (item 3).
- `lib/eval/` is untouched; the interpreter has no representation table.

## Bookkeeping

- `specs/todos/2026-09-10-type-kinds.md` filed with this spec; `git mv` to
  `specs/progress/` when the last phase lands.
- `specs/features/compiler-pipeline.md`: the pass table gains `Kind`, and the
  `Repr` row loses its registration note.
- No `CHANGELOG.md` entry: this is an internal refactor with no observable
  effect. If any phase produces one, that phase has a bug.
- `repr.ml`'s module doc is corrected as part of Phase 1 whether or not the
  rest lands — it currently documents a purity the module does not have.
