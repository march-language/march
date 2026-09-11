# Type Kinds Implementation Plan

> **Status: landed 2026-09-11** (commits 4577c5f3 … ead273a3 on
> `claude/oxcaml-learning-applications-821c17`). Deviations from the plan as
> written, and what the migration found, are in
> `specs/progress/2026-09-10-type-kinds.md`. Task 2.x batches were oracle-gated
> per batch (2a / 2b / 2c) with per-file commits, not oracle-per-file; the
> `llvm_ty` family migrated with Phase 3b rather than in Phase 2.

**Design:** `specs/2026-09-10-type-kinds-design.md` (read it first; this plan
does not restate the rationale).

**Goal:** One `kind` record per monomorphic type, computed once per module and
threaded as a value, replacing the scattered per-type predicates in
`rc_types.ml` / `repr.ml` and the process-global unboxed registry with its
never-cleared `_forced_off` latch. Strictly behaviour-preserving: byte-identical
LLVM IR over the oracle corpus at the end of every task, unmoved TIR
snapshots, full suite green.

**Architecture:** Four phases. Phase 1 introduces `Kind` and makes the old
entry points thin wrappers over it (no call-site change). Phase 2 migrates
call sites one file per commit. Phase 3 threads the table through
`Contract_pipeline` and the emitter context and deletes the globals — the only
phase that changes *when* anything is computed. Phase 4 removes the
now-empty modules and renames the two mis-named `is_closure_ty` functions.

**Proof:** `scripts/ir-oracle.sh` (≈240 programs) proven RED before it is
trusted GREEN; run under a private `HOME`. Plus `scripts/run-tests.sh`,
`test_jit`, the LSP suites, and (Phase 3 only) a real `forge build`.

**Tech stack:** OCaml 5.3.0, dune, alcotest. No new dependencies.

---

## Global rules for every task

- **One dune per worktree.** Never run `scripts/run-tests.sh` while another
  dune build or oracle run is in flight; its `dune shutdown` SIGKILLs whatever
  is mid-run.
- **Exit codes, never through a pipe.** `cmd > log 2>&1; rc=$?` on its own
  line. The harness's "completed (exit code 0)" for a backgrounded pipeline is
  `tail`'s exit code.
- **Oracle under a private HOME:** `HOME=$SCRATCH/home scripts/ir-oracle.sh …`.
  `~/.cache/march` is shared across worktrees and its cached spans carry other
  worktrees' absolute paths.
- **Build the target that restages runtime/stdlib** before oracle or tests:
  `dune build --root . bin/main.exe test/run_codegen.exe` is enough for the
  oracle; `scripts/run-tests.sh` does its own.
- **Explicit `git add` paths.** Never `-A`, `.`, or `-a`.
- **Snapshots must not move.** If `test/snapshots/` diffs in any task, stop:
  that task has a semantic change in it. Do not regenerate.
- **No CHANGELOG entry** for any task. An observable change is a bug here.

---

## Phase 0 — Prove the instrument

### Task 0.1: Baseline and RED proof

- [ ] Build: `dune build --root . bin/main.exe > $SCRATCH/build.log 2>&1; echo rc=$?`
- [ ] Baseline: `HOME=$SCRATCH/home scripts/ir-oracle.sh baseline $SCRATCH/ir-base`
      → expect `emitted=` ≥ 240, `baseline recorded`.
- [ ] Perturb: in `lib/tir/contract_pipeline.ml` temporarily replace
      `if opt then Known_call.run ~changed:(ref false) tir else tir` with
      `tir`. Rebuild. `… ir-oracle.sh check $SCRATCH/ir-base` → **must exit 1**
      with hundreds of differing lines. Record the count in the task log.
- [ ] Revert the perturbation (`git checkout lib/tir/contract_pipeline.ml`).
      Rebuild. `check` → **must print `IR IDENTICAL`**, exit 0.
- [ ] Commit nothing. The baseline directory is the artifact; note its path.

### Task 0.2: Full-suite baseline

- [ ] `scripts/run-tests.sh > $SCRATCH/suite-p0.log 2>&1; echo rc=$?` → rc=0,
      and record the 12 per-suite counts. These are the numbers every later
      phase must reproduce exactly (modulo tests this plan adds).

---

## Phase 1 — Introduce `Kind`; old entry points become wrappers

Nothing outside `lib/tir/{kind,repr,rc_types}.ml` changes in this phase. The
oracle must be IDENTICAL after each task.

### Task 1.1: `kind.mli` + `kind.ml` skeleton — types and `build`

- [ ] Create `lib/tir/kind.mli`:
  ```ocaml
  type repr =
    | Boxed
    | Newtype of Tir.ty
    | Niche   of { payload : Tir.ty; tagged : bool }
    | Unboxed of { ctor : string; fields : Tir.ty list }

  type layout = Imm | Flt | Vec of int | Agg of string | Heap | Cell | Erased

  type kind = {
    layout : layout; repr : repr; llvm_ty : string;
    needs_rc : bool; borrowable : bool;
    niche_ok : bool; needs_tag : bool;
    closure_free : bool; float_free : bool; linear_free : bool;
  }

  type table

  val build :
    ?externs:Tir.extern_decl list -> ?unboxing:bool ->
    collision_set:(string, string list) Hashtbl.t ->
    Tir.type_def list -> table
  val rebind : table -> Tir.type_def list -> table
  (** Same unboxed decision, new type_defs, fresh memo. = old rebind_registration. *)
  val type_defs : table -> Tir.type_def list
  val collision_set : table -> (string, string list) Hashtbl.t

  val of_ty : table -> Tir.ty -> kind
  val find_variant : table -> string -> (string * Tir.ty list) list option
  val is_actor_struct_type : table -> string -> bool
  val is_niche_shaped : table -> string -> bool
  val niche_repr_of_concrete : table -> string -> repr option

  val unboxed_of_type_name : table -> string -> (string * Tir.ty list) option
  val unboxed_of_llvm_ty : table -> string -> (string * string * Tir.ty list) option
  val unboxed_types : table -> (string * string * Tir.ty list) list
  val unboxed_llvm_name : string -> string
  val is_scalar_field : Tir.ty -> bool
  val max_unboxed_arity : int
  val empty : table   (** no type_defs, nothing unboxed; for callers with no module *)
  ```
- [ ] `lib/tir/kind.ml`: `table = { k_type_defs; k_collision; k_unboxed :
      (string, string * Tir.ty list) Hashtbl.t; k_unboxed_by_llvm; k_memo :
      (Tir.ty, kind) Hashtbl.t }`. `build` ports the body of
      `Repr.set_unboxed_types` **verbatim** (same exclusions, same order),
      minus the three global reads (`_forced_off`, env, `enabled`) which
      collapse into the `?unboxing` argument. `rebind` copies with new
      `k_type_defs` and an empty memo.
- [ ] Add `kind` to `lib/tir/dune` `modules`, before `repr`.
- [ ] Build. Oracle IDENTICAL (nothing calls it yet). Commit:
      `refactor(kind): add Kind table skeleton and build (no consumers)`.

### Task 1.2: Port the pure classifiers into `Kind.of_ty`

- [ ] Port `find_variant`, `is_actor_struct_type`, `is_niche_shaped`,
      `niche_payload_ok`, `repr_of_ty`, `payload_needs_tag`,
      `niche_repr_of_concrete` from `repr.ml` into `kind.ml`, each taking
      `table` instead of `(?collision_set, type_defs)`, with
      `unboxed_of_type_name name` becoming `Hashtbl.find_opt t.k_unboxed name`.
      **Copy the doc comments verbatim** — they are the fix history.
- [ ] Port `needs_rc` and `borrow_eligible` from `rc_types.ml` as the
      `needs_rc` / `borrowable` fields. **Move the whole ~130-line module doc
      of `rc_types.ml` into `kind.ml` verbatim** above them.
- [ ] Port `llvm_ty` from `llvm_ctx.ml` as the `llvm_ty` field (the
      `Repr.unboxed_of_type_name` arm becomes a table lookup). Do **not**
      change `llvm_ctx.ml` yet.
- [ ] `layout` is derived from the same match: Int/Bool/Unit/Atom → `Imm`;
      Float → `Flt`; unboxed TCon → `Agg (unboxed_llvm_name name)`; SIMD
      vector TCons (whatever `Llvm_ctx.vec_tys`' March-name table maps) →
      `Vec tag`; tuple/record → `Cell`; TVar → `Erased`; everything else
      `Heap`. `layout` is **unread** in this refactor; it must simply be
      total.
- [ ] `of_ty` memoises on the table; `k_memo` is keyed by structural
      `Tir.ty`.
- [ ] Unit tests (new file `test/test_kind.ml`, registered in `run_codegen`):
      - the `rc_types` truth table and divergence-set test, **copied** from
        `test_codegen.ml` and retargeted at `Kind.of_ty Kind.empty`;
      - `repr` classification over a fixture: Boxed, Newtype, Niche(Int,
        tagged), Niche(String, untagged), Float-payload newtype stays Boxed,
        Unboxed Vec3, actor-message forced Boxed, colliding forced Boxed,
        extern-crossing stays Boxed, Option(Option(Int)) payload not niche_ok.
- [ ] Build + tests + oracle IDENTICAL. Commit:
      `refactor(kind): port representation and RC classifiers into Kind.of_ty`.

### Task 1.3: Deep crossing facts

- [ ] Implement `closure_free` and `float_free` in `of_ty`: walk constructor
      args / record fields through `find_variant` and `TDRecord`, with a
      `visited : (string, unit) Hashtbl.t` so recursive and mutually
      recursive types terminate. `TFn` ⇒ not closure_free; `TFloat` ⇒ not
      float_free; a `TDClosure` ⇒ not closure_free. There is **no**
      `linear_free`: linearity is erased at lowering and lives on
      `Tir.var.v_lin` (see the design's "Crossing facts"). Do not invent a
      linearity channel here.
- [ ] Tests in `test_kind.ml`: closure in a record field; Float nested two
      variants deep; recursive `List`-like type terminates; mutually
      recursive pair terminates; `int list`-shaped type is closure_free and
      float_free.
- [ ] Oracle IDENTICAL (unread fields). Commit:
      `refactor(kind): compute deep crossing facts (unread)`.

### Task 1.4: `repr.ml` and `rc_types.ml` become wrappers

- [ ] `repr.ml`: `type repr = Kind.repr = Boxed | Newtype of Tir.ty | …`
      (type re-export, so `Repr.Boxed` keeps compiling at every call site).
- [ ] Replace `_unboxed` / `_unboxed_by_llvm` with `_current : Kind.table
      option ref`. Keep `_registered_from` and `_forced_off` **unchanged** —
      they go in Phase 3.
  - `set_unboxed_types ?collision_set ?externs ?enabled type_defs` →
    `_current := Some (Kind.build ?externs ~unboxing:(enabled && not
    !_forced_off && not (Lazy.force unboxing_disabled)) ~collision_set
    type_defs)`; set `_registered_from` as before.
  - `clear_unboxed_types` → `_current := None; _registered_from := None`.
  - `ensure_unboxed_types`, `rebind_registration`, `force_disable`: same
    control flow as today over the new cells.
  - `unboxed_of_type_name n` → lookup in `_current` (or `None`);
    `unboxed_types ()`, `unboxed_of_llvm_ty` likewise.
- [ ] Wrapper cache: `table_for ~collision_set type_defs` returns `_current`'s
      table when **both** `type_defs` and `collision_set` are physically equal
      to the table's; otherwise a transient table built with
      `Kind.rebind`-style sharing of `_current`'s unboxed set (or empty) and
      the **call-site** `collision_set`. Keep a 4-entry physical-identity
      cache so hot paths are memoised. This preserves today's exact semantics:
      call-site `type_defs`/`collision_set` for shape and collision checks,
      the global registry for the unboxed set.
- [ ] `repr_of_ty`, `is_niche_shaped`, `niche_payload_ok`,
      `payload_needs_tag`, `niche_repr_of_concrete`, `find_variant`,
      `is_actor_struct_type` → one-liners over `Kind` + `table_for`. Delete
      their bodies.
- [ ] `rc_types.ml`: `needs_rc ty = (Kind.of_ty (Repr.current_or_empty ()) ty).needs_rc`,
      same for `borrow_eligible`, `is_unboxed_aggregate`. Delete the bodies.
      Leave a 3-line module doc pointing at `kind.ml`.
- [ ] **Correct `repr.ml`'s module doc**: it no longer claims to be a pure
      function with no threaded state; say what it is now (a process-global
      holder of one `Kind.table`, scheduled for removal in Phase 3).
- [ ] Build; `scripts/run-tests.sh codegen` (rc_types + unboxed groups must
      pass unchanged); oracle IDENTICAL. Commit:
      `refactor(kind): repr.ml and rc_types.ml delegate to Kind (no call-site change)`.

### Task 1.5: Phase-1 gate

- [ ] Full `scripts/run-tests.sh` → same 12 counts as Task 0.2 plus the new
      `test_kind` cases. `git diff --stat test/snapshots/` empty. Oracle
      IDENTICAL. Record in the task log.

---

## Phase 2 — Migrate call sites, one file per commit

Each task: migrate the file's `Repr.*` / `Rc_types.*` / `llvm_ty` reads to
`Kind.of_ty <table>` where the table comes from (a) `ctx.k_table` in emitter
files, or (b) a `?k_table` optional parameter added to the pass entry point,
defaulting to `Repr.current_or_empty ()`. Build, `run-tests.sh codegen`,
oracle IDENTICAL, commit `refactor(kind): <file> reads Kind`.

### Task 2.0: `Llvm_ctx.ctx` gains `k_table`

- [ ] Add `k_table : Kind.table` to `ctx`. In `make_ctx`, after the existing
      registration block, `k_table = Repr.current_or_empty ()` — wait: this
      must be the table for **this ctx's** `type_defs`/`collision_set`, so use
      `Repr.table_for ~collision_set type_defs`. `llvm_ty` stays a free
      function for now; add `llvm_ty_k : Kind.table -> Tir.ty -> string` =
      `(Kind.of_ty t ty).llvm_ty` and migrate `llvm_ctx.ml`'s own 18 sites.
- [ ] **Audit `lower_match.ml` (2 sites) and `typecheck_builtins.ml` (1)**:
      they run **pre-mono**. Determine whether each is a comment, a
      shape-only helper (`find_variant`), or a real representation read. A
      real read pre-mono is a latent bug to file, not to fix here.

### Tasks 2.1 – 2.19 (in this order; counts are today's mentions)

| # | File | Sites | Table source |
|---|---|---|---|
| 2.1 | `llvm_case.ml` | 36 | `ctx.k_table` |
| 2.2 | `llvm_emit_alloc.ml` | 29 | `ctx.k_table` |
| 2.3 | `drop.ml` | 22 | `?k_table` param |
| 2.4 | `repl_jit.ml` | 18 | table built by the JIT with `~unboxing:false` (Phase 3 finishes this; here just read through `ctx`) |
| 2.5 | `alloc_contract.ml` | 10 | `?k_table` param |
| 2.6 | `perceus_core.ml` | 9 | threaded from `Perceus.perceus ?k_table` |
| 2.7 | `llvm_emit.ml` | 7 | `ctx.k_table` |
| 2.8 | `escape.ml` | 7 | `?k_table` param |
| 2.9 | `borrow.ml` | 7 | `?k_table` param |
| 2.10 | `perceus.ml` | 6 | `?k_table` param |
| 2.11 | `llvm_eq.ml` | 6 | `ctx.k_table` |
| 2.12 | `contract_pipeline.ml` | 6 | builds/holds it (see Phase 3) |
| 2.13 | `llvm_ctor_desc.ml` | 4 | `ctx.k_table` |
| 2.14 | `trmc.ml` | 3 | `?k_table` param |
| 2.15 | `perceus_scrut.ml` | 3 | threaded |
| 2.16 | `llvm_emit_data.ml`, `llvm_emit_arith.ml` | 3+3 | `ctx.k_table` |
| 2.17 | `llvm_toplevel.ml`, `llvm_data.ml`, `lower_actor.ml`, `tir.ml` | 1 each | inspect; most are comments |
| 2.18 | `lsp/lib/analysis.ml` | 1 | `pipe.final` → table from the pipeline result (add `k_table` to `Contract_pipeline.result`) |
| 2.19 | `test/test_codegen.ml`, `test_properties.ml`, `test_trmc.ml` | 61+2+1 | leave on the wrappers until Phase 3 rewrites them |

- [ ] After 2.19: `grep -rn "Rc_types\.\|Repr\.\(repr_of_ty\|is_niche_shaped\|niche_payload_ok\|payload_needs_tag\|niche_repr_of_concrete\|find_variant\|is_actor_struct_type\|unboxed_of\)" lib lsp bin` returns only `repr.ml`, `rc_types.ml`, and `contract_pipeline.ml`.

### Task 2.20: Phase-2 gate

- [ ] Full suite = Phase-1 counts. Snapshots unmoved. Oracle IDENTICAL.

---

## Phase 3 — Thread the table; delete the globals

This phase changes initialisation order by construction. Its gate is larger.

### Task 3.1: `Contract_pipeline` owns the table

- [ ] Where `Repr.set_unboxed_types` is called (after Defun): `let k0 =
      Kind.build ~externs:tm_externs ~unboxing:(not is_js && not
      (Lazy.force no_unbox_env)) ~collision_set tm_types`. The `MARCH_NO_UNBOX`
      lazy moves here from `repr.ml`.
- [ ] Pass `~k_table:k0` to every pass migrated in Phase 2 (make the
      parameters **required** now; delete the `Repr.current_or_empty`
      defaults).
- [ ] Where `Repr.rebind_registration` is called (before emit): `let k =
      Kind.rebind k0 tir.tm_types`. Put `k` in `Contract_pipeline.result` as
      `k_table`, and thread it into `Alloc_contract`.
- [ ] `bin/main.ml` passes `result.k_table` to `Llvm_emit.emit_module` /
      `make_ctx ~k_table`. `make_ctx` **stops registering**: it takes
      `~k_table` (required) and builds the preamble from
      `Kind.unboxed_types k_table`.
- [ ] Build; oracle IDENTICAL; `run-tests.sh codegen`. Commit.

### Task 3.2: REPL and JIT build their own tables

- [ ] `llvm_repl.ml` (4 `make_ctx ~repl:true` sites) and `repl_jit.ml`:
      `Kind.build ~unboxing:false ~collision_set type_defs` and pass it. Delete
      the `Repr.force_disable ()` calls. `Perceus.perceus ~repl:true` and
      `Escape.escape_analysis` receive the same table.
- [ ] `HOME=$SCRATCH/home scripts/repl_smoke_test.sh` (or whatever the REPL
      smoke script is named in `scripts/`; baseline 48/6) — same numbers.
- [ ] `scripts/run-tests.sh test_jit` green. Commit.

### Task 3.3: Delete the registry

- [ ] `repr.ml`: delete `_current`, `_registered_from`, `_forced_off`,
      `set_unboxed_types`, `ensure_unboxed_types`, `clear_unboxed_types`,
      `rebind_registration`, `force_disable`, `unboxing_disabled`,
      `table_for`, `current_or_empty`, and every wrapper. What remains:
      the `repr` type re-export and nothing else (or delete the file if the
      re-export is unneeded after Phase 2 — check with `grep -rn "Repr\."`).
- [ ] Rewrite the tests that used the registry (`test_codegen.ml` unboxed
      group ×6, rc_types ×2, `test_properties.ml`, `test_trmc.ml`) to build a
      `Kind.table` explicitly. The `boxed_control` case builds with
      `~unboxing:false`.
- [ ] **New tests** (`test_kind.ml`):
  - *determinism*: `build` twice from the same inputs → structurally equal
    `of_ty` results for every type in the fixture; two different modules in
    one process → neither table sees the other's unboxed entries.
  - *latch removal*: build a REPL-style table (`~unboxing:false`), then a
    normal one, in the same process; assert the second **does** unbox `Vec3`.
    This test is the readable proof the latch is gone; it would have failed
    before this task.
- [ ] Build; oracle IDENTICAL. Commit:
      `refactor(kind): delete the process-global unboxed registry`.

### Task 3.4: Phase-3 gate (larger than the others)

- [ ] Full `scripts/run-tests.sh` = Phase-2 counts + new tests.
- [ ] `scripts/run-tests.sh lsp utf16 jsonrpc incremental query_cli` green
      (the oracle is blind to `lsp/`).
- [ ] `scripts/run-tests.sh test_jit` green.
- [ ] Oracle IDENTICAL.
- [ ] Real project: `forge build` of one repo in `~/code` that uses the
      worktree compiler (see the worktree dev-compiler memory: `MARCH_HOME=`
      + cd-wrapper; a PATH shim alone does not work for forge). Zero
      diagnostics, binary runs.
- [ ] Snapshots unmoved. If they moved, **stop and explain**; do not
      regenerate.

---

## Phase 4 — Remove the empty modules and the misnomers

### Task 4.1: Delete `rc_types.ml`

- [ ] `grep -rn "Rc_types" lib lsp bin test` → zero. Delete the file, remove
      from `dune`. (Its doc moved in Task 1.2.) Commit.

### Task 4.2: The two `is_closure_ty`

- [ ] They are **not** duplicates: `borrow.ml:238` tests a closure-struct
      *name*; `cprop.ml:75` tests `TFn | TVar` ("indirectly callable").
      Rename to `is_clo_struct_ty` and `is_indirect_callable_ty` respectively.
      Do not unify. Commit.

### Task 4.3: Docs and bookkeeping

- [ ] `specs/features/compiler-pipeline.md`: add `Kind` to the pass/module
      table; remove the `Repr` registration note; update the pass-order note
      to say the table is built after Defun and rebound before emit.
- [ ] `scripts/check-docs.sh` green.
- [ ] `git mv specs/todos/2026-09-10-type-kinds.md specs/progress/` and append
      a "Landed" section: oracle counts, the RED-proof line count from Task
      0.1, the two new tests, and anything the migration found (the pre-mono
      audit in Task 2.0 in particular).
- [ ] Final full suite; record counts. Commit.

---

## Out of scope (do not do these while in here)

- Any representation change, including the "nullary constructor is not always
  free" observation, `Option(Float)`, and Float layout.
- Reading `layout` or the `*_free` fields from any pass.
- Touching `lib/eval/`.
- Adding `.mli` files to modules other than `kind`.
