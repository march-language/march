# Strict Cap unification — root-cause is qualified-prebind erasure, not `unify`

**Date:** 2026-07-08
**Status:** ready to execute (subagent-driven-development)
**Slice kind:** compiler type-soundness fix (general, exploited via proof caps)
**Author of plan:** feasibility-validated against oracle `_build/default/bin/main.exe` @ branch `docs/core-march-types-skeleton` HEAD `66b6716a`, plus a fully instrumented copy of the compiler (debug prints of every fn scheme, every `unify`, every `EVar` resolution) built and run in an isolated tree.

---

## TL;DR for the reviewer

The brief hypothesised that **`Cap`-type-argument unification is lax in `unify`**. **That hypothesis is FALSE.** `unify`'s `TCon` arm (`typecheck.ml:2341`) is strict and never erases a `Cap` argument. The real defect is elsewhere and is **not Cap-specific**: an **unannotated function defined inside a nested `mod` gets its *qualified* name (`Mod.fn`) prebound to a fresh monomorphic type variable that is NEVER reconciled with the function's real inferred scheme.** Because desugar rewrites every intra-nested-module reference to the qualified form, every call to such a helper resolves to that stale `Mono '_v` placeholder — which behaves as `∀. a -> b` and **erases the type of anything flowed through it** (base types, ADTs, and `Cap` alike). The proof-cap forge is one exploitation of a general memory-safety hole.

The fix is **one small, bounded change in `check_decl`'s `DFn` branch** (reconcile the qualified prebind with the real scheme, guarded to only touch the bare-placeholder case). It was implemented and validated end-to-end in the instrumented tree: all forge routes flip exit 0→1, all four must-preserves stay exit 0, and it is **codegen-byte-identical** (fix-on vs fix-off produce the same test results). **Strict Cap unification is NOT needed and would be the wrong fix.**

---

## Confirmed root cause (with file:line + internal-representation evidence)

### The reproductions (all on the freshly built oracle)

| # | Program shape | Exit (pre-fix) | Desired |
|---|---------------|:---:|:---:|
| F1 | Nested proof-cap forge: `mod T do mod Db do proof cap P end mod App do … fn id(x) do x end; fn consume(c:Cap(Db.P)):Int …; fn attack(cap:Cap(IO)):Int do consume(id(cap)) end end end` | **0 (FORGE)** | 1 |
| F2 | Same, `id` laundering `Cap(IO)`→`Cap(IO.Network)` (`use_net(id(cap))`) | **0 (FORGE)** | 1 |
| F3 | **Non-Cap, non-proof:** nested `Box(a)`, `need_int(id(bx))` where `bx=Box("hi")` | **0 (FORGE)** | 1 |
| F4 | **General memory-safety break:** nested `id`, `let n = 12345; takes_str(id(n))` where `takes_str(s:String)` calls `string_length` | **0 (FORGE)** | 1 |
| F5 | 3-deep (`mod Outer > Mid > App`) Box forge | **0 (FORGE)** | 1 |
| P1 | DIRECT `consume(cap)` (no `id`) | 1 | 1 (unchanged) |
| P2 | DIRECT `use_net(cap)` `Cap(IO)`→`Cap(IO.Network)` | 1 | 1 (unchanged) |
| P3 | **`p6_capnarrow`** — `use_net(cap_narrow(cap))` legit IO narrow | 0 | 0 (unchanged) |
| P4 | **`id_twouse`** — `fn id(x) do x end` used at Int AND String (legit polymorphism) | 0 | 0 (unchanged) |
| P5 | Nested `id` **annotated** `fn id(x:a):a` → Box/Cap forge | 1 | 1 (already OK — see why) |
| P6 | **`pfn id`** (private) → Box forge | 1 | 1 (already OK — see why) |

### The two ingredients (both required; direct calls and single-module are always safe)

1. **`desugar`'s `qualify_module_refs` rewrites intra-nested-module references to the qualified form.** `lib/desugar/desugar.ml:2099` (`qualify_module_refs`), `:2049` (`qualify_level`), `:1991` (`make_qualifier`). Inside `mod App`, a bare `id(bx)` in `attack`'s body is rewritten to `EVar "App.id"`. The entry file's own top-level `mod` name is stripped (`entry_prefix = ""`), so for `mod T do mod App …` the ref becomes `App.id`; for `mod Outer > Mid > App` it becomes `Mid.App.id`. This is CORRECT and load-bearing for codegen (TIR emits the fully-qualified definition name; a mismatch would undefined-symbol at link — that is exactly what the `test/native/nested_mod_qualcall.march` regression fixture guards).

2. **`prebind_mod_members` prebinds the qualified name to a bare mono var for UNANNOTATED public fns, and it is never reconciled.** `lib/typecheck/typecheck.ml:8519` `prebind_mod_members`:
   ```
   8522  | Ast.DFn (def, _) when def.fn_vis = Ast.Public ->
   8523    let qname = prefix ^ "." ^ def.fn_name.txt in
   8526    let sch = match prebind_fn_scheme def with
   8527      | Some s -> s                       (* has annotations → real arrow scheme *)
   8528      | None -> Mono (fresh_var 1)         (* UNANNOTATED → bare placeholder *)
   8530    bind_var qname sch e
   ```
   `prebind_fn_scheme` (`:8448`) returns `None` unless the fn has BOTH a return annotation AND all params annotated (`:8479-8486`). `fn id(x) do x end` has neither, so `App.id` is bound to `Mono (fresh_var 1)` — an unbound var.

   The reconciliation gap: `check_decl`'s `DFn` branch (`:7093-7098`) computes the real scheme via `check_fn` and rebinds only the **BARE** name:
   ```
   7096  let sch = check_fn env def sp in
   7098  bind_var def.fn_name.txt sch env      (* rebinds "id", NOT "App.id" *)
   ```
   The DMod branch *does* re-export `inner_env.vars` under `Mod.k` (`:7375-7379`, `bind_vars new_names`) — but only into the **outer** env, AFTER the inner module is fully checked. During the inner check (when `attack`'s body is inferred), the only `App.id` visible in `inner_env.vars` is the stale `Mono (fresh_var 1)`.

### Internal-representation evidence (instrumented compiler)

Debug print of every fn's final scheme and every `EVar` resolution inside `mod App`:

- Nested case, `attack`'s body: `App.need_int -> Mono Box(Int) -> Int` (correct), **`App.id -> Mono s3`** (a bare unbound var — NOT the real `Poly(a -> a)`), `bx -> Mono Box(String)` (correct).
- The `id` DEFINITION's scheme is correctly `Poly([…], i57 -> i57)` — the definition is fine; only the *qualified reference target* is wrong.
- Single-module (`mod App` is the entry's own top mod): `attack` resolves `id -> Poly r3 -> r3` and `need_int -> Mono Box(Int) -> Int`, and the trace shows `unify(Box(String), Box(Int))` firing → mismatch → exit 1. In the nested case that `unify` **never fires** because `App.id : Mono s3` takes `infer_app`'s `TVar` branch (`typecheck.ml:4676`): it binds `s3 = TArrow(Box(String), ?ret)` with `?ret` a *fresh, independent* var — the domain and codomain are decoupled, so no `Box(String) ~ Box(Int)` constraint is ever generated. That is the erasure.

### Why the asymmetries in the brief resolve

- **"Box enforced through `id`, Cap erased" is a testing artifact.** The brief's Box control was written as a *single* `mod App`; the forge was written as *nested* `mod T do mod App`. In the **single**-module shape, Box is enforced (no qualification, no stale prebind). In the **nested** shape, Box is ALSO erased — verified live (`need_int(id(bx))` nested → exit 0). The distinguishing variable is nesting, not the type kind.
- **Direct calls reject (P1/P2)** because a direct `consume(cap)` unifies the argument straight against `consume`'s real annotated param type — no laundering var in between.
- **Annotated `id` (P5) rejects** because `prebind_fn_scheme` then builds a real `Poly` scheme for `App.id` — no stale placeholder.
- **Private `pfn id` (P6) rejects** because `prebind_mod_members` only prebinds PUBLIC fns; `App.id` is absent, so the reference falls through `resolve_qualified_var` / the suffix-strip fallback (`typecheck.ml:3620`) to the local `id : Poly`.

### Why `unify` is exonerated

`unify`'s `TCon` arm (`typecheck.ml:2341`) is strict:
`| TCon (n1,a1), TCon (n2,a2) -> if n1=n2 && arity then List.iter2 unify a1 a2 else mismatch`.
`Cap(IO)` and `Cap(Db.P)` become `TCon("Cap",[TCon("IO",[])])` and `TCon("Cap",[TCon("Db.P",[])])` (proof-cap arg is a rigid nominal `TCon`, confirmed: direct `consume(cap)` rejects via this arm). The forge never *reaches* this arm because `App.id`'s decoupled result var absorbs the argument without producing a `Cap(IO) ~ Cap(Db.P)` constraint. **Making `unify` stricter would not help** (there is nothing to unify) and would risk breaking legitimate `cap_narrow` narrowing (which relies on an unbound var binding to a concrete sub-cap).

---

## The fix (DECIDED — implement exactly this)

**Reconcile the qualified prebind with the real inferred scheme in `check_decl`'s `DFn` branch**, guarded to only overwrite a bare `Mono (TVar unbound)` placeholder (the unannotated-fn case). This exactly mirrors the existing bare-name placeholder reconciliation in `check_fn` (`typecheck.ml:5303-5320`), lifted to the qualified name.

`lib/typecheck/typecheck.ml`, replace the `DFn` branch body (`:7095-7098`):

```ocaml
  | Ast.DFn (def, sp) ->
    let sch = check_fn env def sp in
    discharge_constraints env sp;
    let env = bind_var def.fn_name.txt sch env in
    (* Reconcile the QUALIFIED prebind (Mod.fn) with the real inferred scheme.
       desugar's qualify_module_refs (lib/desugar/desugar.ml) rewrites every
       intra-nested-module reference to the qualified form (e.g. `App.id`), and
       prebind_mod_members bound that name to a fresh `Mono (fresh_var 1)` for an
       UNANNOTATED public fn (prebind_fn_scheme returned None).  Without this
       rebind, sibling fns in the same nested module resolve the stale
       placeholder — a decoupled `?a -> ?b` — which erases the type of anything
       laundered through the fn (proof-cap forge, and general unsoundness).
       Only overwrite when the qualified binding is STILL the bare placeholder;
       an already-concrete scheme (from prebind_fn_scheme, or a same-file default-
       arg sibling) must be left intact — mirrors check_fn's placeholder guard. *)
    if env.cap_qual_prefix <> "" then
      let qname = env.cap_qual_prefix ^ "." ^ def.fn_name.txt in
      (match StrMap.find_opt qname env.vars with
       | Some (Mono (TVar r)) when (match !r with Unbound _ -> true | _ -> false) ->
         bind_var qname sch env
       | _ -> env)
    else env
```

**Why the prefix matches.** `env.cap_qual_prefix` accumulates exactly as `prebind_mod_members`'s `prefix` does (doc at `typecheck.ml:488-498`): `""` at the entry module, then the nested module names, entry mod stripped. The DMod branch sets it (`:7275-7277`). Instrumentation confirmed `cap_qual_prefix = "App"` at the `id` definition, matching the prebind key `App.id` and the desugared reference `App.id`; verified through 3-deep nesting (F5 closes).

**Why it closes the forge in ALL flows.**
- *Direct* (P1/P2): already rejected by argument-vs-param unification; unchanged.
- *`id`-launder* (F1–F5): the qualified reference now resolves to the real `Poly(a -> a)`; `infer_app`'s `TArrow` branch (`:4662`) unifies the argument against the *linked* param/return, so `Cap(IO) ~ Cap(Db.P)` (F1) / `Box(String) ~ Box(Int)` (F3) / `Int ~ String` (F4) fires → mismatch. Verified live: F1–F5 all flip to exit 1.
- *Container / HOF launder*: any polymorphic wrapper `fn wrap(x) do (x,0) end` defined in a nested module was subject to the SAME erasure and is closed the same way (its qualified prebind is now reconciled). A single-module container launder is already rejected today (verified).

**Why it preserves the four must-preserves.**
1. **`cap_narrow` legit narrowing** (`use_net(cap_narrow(cap))` at `Cap(IO.Network)`): unaffected — `cap_narrow`'s result is a genuine unbound var binding to an IO sub-cap; the fix does not touch `unify` or `cap_narrow`. Verified exit 0.
2. **`needs` gate** (`cap_subsumes`, `typecheck.ml:1241`): a separate pass; untouched.
3. **Legit polymorphism** (`id_twouse`, HOFs, `identity`/`compose`/`map` in the prelude): the fix only *reconciles* the qualified name to the fn's OWN correctly-generalized scheme — it never over-monomorphises. `id` remains `∀a. a -> a`; two uses at Int and String stay green. Verified.
4. **IO-cap system, actors' `Cap`, `get_cap`/`send_checked`/`revoke_cap`/`is_cap_valid`**: their schemes (`typecheck.ml:1595-1620`) are unchanged; the fix is orthogonal to builtin cap dispatch. A nested `id`-passthrough of `Cap(IO)`→`Cap(IO)` stays exit 0; `is_cap_valid(id(c))` behaves identically fix-on vs fix-off (verified — any exit-1 there is a pre-existing `needs`-gate effect, not the fix).

**Blast radius.** One branch of one function. It never runs for: single top-level modules (`cap_qual_prefix = ""`), private fns (no qualified prebind), or annotated fns (concrete prebind → guard skips). It is therefore inert for the vast majority of code and surgical for the exact defect.

---

## Fate of the Batch-A `cap_narrow` taint machinery — **KEEP (do not remove or simplify)**

The Batch-A machinery (`cap_producer_ivars` `:517`, `demote_to_monomorphic` `:637`, `tag_cap_producer_result`, the `unify` proof-cap-forge hook `:2296-2337`, `mint_cap` gate, `cap_narrow_factory_fns`) solves a **DIFFERENT, orthogonal** problem and is **not subsumed** by this fix. Evidence:

- The **single-module** `cap_narrow`→proof-cap forge (`consume(cap_narrow(cap))` with `consume:Cap(Db.P)`) is rejected today **only** by Batch-A (this fix is nested-module-only and does not run there). Verified: exit 1 with Batch-A present; this fix contributes nothing.
- That route is fundamentally a **genuine unbound-var-binds-to-a-proof-cap** event (`cap_narrow : Cap(IO) -> Cap(a)`, `a := Db.P`). A stricter `unify` cannot reject it without also rejecting legitimate IO narrowing (which is the exact same shape: `a := IO.Network`). Only a *proof-cap-target* discriminator (`env.proof_caps`) can tell them apart — which is precisely what Batch-A's `unify` hook does. **This fix does not and cannot replace it.**

**Relationship:** COMPLEMENTARY. This fix closes the *qualified-prebind erasure* that let ANY value (including a `cap_narrow` result) launder through a nested unannotated helper untyped; Batch-A closes the *`cap_narrow`-mints-a-proof-cap* concern regardless of laundering. Both are needed.

**Container-launder gap (from the review) — still stands, handle separately.** The review noted `tag_cap_producer_result` (`:~660`) is shallow/non-recursive, so a `cap_narrow` result wrapped in a tuple/Option through a poly factory can still forge in some shapes. This fix does **not** close that (it is about qualified-prebind erasure, not about the recursive propagation of the cap-producer taint through container constructors). The simple single-module tuple-launder probed here happens to reject, but the review's deeper container/factory shapes remain a **separate Batch-A follow-up** (recursive tagger). Flag it; do not fold it into this plan.

---

## Global Constraints (binding — copy into every task's working context)

- **Worktree only.** All work happens in
  `/Users/80197052/code/march/.claude/worktrees/hopeful-kapitsa-9f49f3`. NEVER
  `cd` outside it; never grep or edit a tree outside it. A concurrent session's
  `git reset` in the main repo silently reverts main-repo edits — stay in the
  worktree.
- **Build:** `dune build --root .` (dune on PATH at
  `/Users/80197052/.opam/march/bin`). **NEVER** `eval $(opam env ...)` or any
  opam-env preamble. Run long builds in the **background** and poll; a timed-out
  foreground `dune` orphans a lock-holding child that wedges later builds — if
  builds hang, `lsof _build/.lock` and `kill -9` the orphan.
- **Oracle:** `_build/default/bin/main.exe --check <file>`. NEVER pipe
  `march --compile` output (the compiler child holds the pipe open and wedges);
  redirect to a file, judge by `$?`, read the file separately.
- **Full-suite gate (six runners):** before any commit that touches the compiler,
  run `scripts/run-tests.sh` (full, ~17s; it shuts down the stale dune daemon,
  builds, runs binaries directly). Judge dune/alcotest by **`$?`**, not tail
  output — rule failures hide above a green summary. The RED→GREEN unit test is
  the primary gate.
- **Conformance gates:** `bash specs/lang/types/check_types.sh` must end
  `=== core-march-types: N passed, 0 failed ===` and exit 0. `scripts/check-docs.sh`
  (doc-freshness lint) must pass.
- **Git hygiene:** stage files **explicitly by name** — NEVER `git add -A`, `git
  add .`, `git add *`, or `git commit -am`. **NEVER `git stash`** in a worktree
  (the stash stack is shared across all sessions — file-copy swap if you must set
  work aside). **NO `Co-Authored-By`** trailer on any commit. This branch is not a
  default branch; commit directly on it.
- **Spec bookkeeping (CLAUDE.md rule):** update `specs/todos.md` (move/flip the
  finding) and, when a capability lands, `specs/progress.md` in the SAME commit as
  the change.

---

## Baseline established (before you start — reproduce to confirm)

On the real worktree binary (NOT a copy — see RISK note on tree copies):
- `scripts/run-tests.sh` full six-runner is **GREEN** (`$? = 0`). The 392-test
  `run_codegen` including the `llvm_ir_validity_gate` passes with **0 IR-gate
  failures** on the real worktree (a rsync'd copy breaks `test/native` stdlib
  resolution and shows spurious IR failures — an artifact of the copy, not of any
  code change; do all validation IN the worktree).
- All F1–F5 forge probes below `--check` **exit 0** (the bug); all P1–P6
  preserve-probes already behave as their "desired" column.

---

## Task sequence

Ordered so the **compiler fix + adversarial unit tests land first** (forge routes
flip 0→1, legit paths stay green, six-runner green), then the Batch-A decision is
recorded, then downstream corpus/docs work is flagged for a later batch.

---

### Task 1 — Adversarial unit tests FIRST (RED), then the fix (GREEN)

**Goal:** lock the behavior with tests that fail on the pre-fix compiler, then make
them pass with the one-branch fix.

**Files:** `lib/typecheck/typecheck.ml`; a typecheck test file under `test/`
(add cases to the existing capability/soundness typecheck suite — grep
`test/test_compiler*.ml` or the file that already houses `--check` exit-code
assertions for proof caps; if none fits cleanly, add a focused
`test/test_nested_mod_soundness.ml` wired into `run_compiler`).

**Adversarial cases (exact `.march` bodies are in this plan's F/P table; use them verbatim).**
RED (must be exit 0 on pre-fix, exit 1 after):
- F1 nested proof-cap `id`-launder → reject (substring: `Cap(Db.P)` / `Cap(IO)` mismatch)
- F2 nested `id`-launder `Cap(IO)`→`Cap(IO.Network)` → reject
- F3 nested `Box(a)` `id`-launder (`Box(String)`→`Box(Int)`) → reject
- F4 nested `id`-launder `Int`→`String` (general memory-safety) → reject
- F5 3-deep nesting Box forge → reject
- container/HOF variant: a nested `fn wrap(x) do (x, 0) end` factory launder → reject
GREEN-STAYS-GREEN (must be exit 0 both before and after):
- P3 `use_net(cap_narrow(cap))` legit IO narrow
- P4 `fn id(x) do x end` used at Int AND String (legit polymorphism)
- nested `id`-passthrough `Cap(IO)`→`Cap(IO)` (identity, no coercion)
- P5 annotated `fn id(x:a):a` nested (already rejects — regression guard that the
  fix didn't change it)
- P6 `pfn id` nested (already rejects — guard)

**Steps:**
1. Add the RED cases; confirm they currently exit 0 (F1–F5) via the oracle before
   touching `typecheck.ml`.
2. Apply the fix from "The fix" section above (the `DFn` branch replacement).
3. `dune build --root .` (background + poll).

**Test cmd:**
```
./_build/default/bin/main.exe --check <each F/P fixture>   # judge by $?
scripts/run-tests.sh                                       # six-runner, judge by $?
```
**Expected exit:** every F* fixture `--check` → 1; every P*/legit fixture → 0;
`scripts/run-tests.sh` → 0 (all four in-process runners green: `run_compiler` 457,
`run_eval` 231, `run_codegen` 392 with 0 IR-gate failures, `run_stdlib` full).

> Validation already performed (instrumented tree): F1–F5 flip to exit 1; P3/P4/
> passthrough stay exit 0; `run_compiler` (457), `run_eval` (231), `run_stdlib`
> (773) all green; `run_codegen` fix-on and fix-off produce byte-identical results
> (the fix is codegen-neutral). Reproduce in the real worktree for the commit gate.

**Commit:** `typecheck: reconcile qualified nested-module prebind — close type-erasure forge (proof caps + general soundness)`. Stage `lib/typecheck/typecheck.ml` and the test file by name. Update `specs/todos.md` in the same commit (flip the finding — see Task 2).

---

### Task 2 — Record the Batch-A decision + finding update

**Goal:** capture the keep/complement decision so a later reviewer does not
mistake the taint machinery for dead code.

**Files:** `specs/todos.md` (and `specs/progress.md` if a capability line is
warranted).

**Steps:**
1. In `specs/todos.md`, flip the "Cap-argument unification unsound through
   polymorphic functions" finding to Done, but **rewrite its title/body** to the
   confirmed root cause: *"qualified-prebind erasure of unannotated nested-module
   fns (general type-soundness hole; proof-cap forge is one exploitation) — FIXED
   in `check_decl`'s DFn qualified reconciliation."* Do not leave the misleading
   "Cap unification" framing.
2. Add a short note that Batch-A (`cap_producer_ivars` / `demote_to_monomorphic` /
   `tag_cap_producer_result` / `unify` proof-cap hook / `mint_cap`) is **retained**
   — it closes the orthogonal single-module `cap_narrow`-mints-a-proof-cap route
   that this fix does not touch.
3. Add a fresh finding for the **still-open** container/factory taint gap
   (`tag_cap_producer_result` shallow / non-recursive) so it is not lost.

**Test cmd:** `scripts/check-docs.sh` (judge by `$?`).
**Expected exit:** 0.
**Commit:** may be folded into Task 1's commit (same-commit bookkeeping is the
CLAUDE.md rule) OR a standalone `docs(spec): record root cause + Batch-A retention`
if Task 1 is already committed.

---

### Task 3 — (FLAG ONLY, do NOT implement here) downstream corpus + reference

A later batch owns these; list them so they are not forgotten, but do NOT plan
them in detail:
- **Conformance corpus witnesses** under `specs/lang/types/` (accept/reject
  `.march` + INDEX counts): reject witnesses for the nested `id`-launder forge
  (F1–F5) and accept witnesses for the legit passthrough / `cap_narrow` narrow.
  Each reject must be IMPOSSIBLE to reject on the pre-fix compiler.
- **Reference prose** in the relevant `specs/lang/` chapter: a rule-numbered
  statement that intra-module references are checked against the referent's real
  (possibly polymorphic) scheme regardless of module nesting — i.e. nesting does
  not weaken type checking.
- The container/factory Batch-A follow-up (recursive `tag_cap_producer_result`).

---

## RISK section

**What is load-bearing / could regress, and the exact probes that de-risk it.**

1. **`cap_qual_prefix` must equal `prebind_mod_members`'s prefix for the guard key
   to match, at every nesting depth.** If they diverged, the fix would silently
   no-op (forge stays open) — a *safe* failure (no false rejects), but it would
   miss the bug. *De-risk:* F1 (1-deep) AND F5 (3-deep) must both flip to exit 1
   (both verified in the instrumented tree). If a future refactor changes either
   prefix convention, these two probes catch it.

2. **Over-broad rebind breaks monomorphization / codegen** (the reason for the
   `Mono (TVar unbound)` guard). An UNGUARDED version that rebinds the qualified
   name even when it already holds a concrete `prebind_fn_scheme` result perturbs
   the scheme identity that TIR lowering/monomorphization keys on — the
   `test/native/nested_mod_qualcall.march` (CRDT.PNCounter) fixture and the
   distributed-node fixtures are the tripwires. *De-risk:* the guard restricts the
   rebind to the bare-placeholder (unannotated-fn) case ONLY; CRDT's helpers are
   annotated (or private), so the guard skips them. Gate: `run_codegen` must show
   **0 IR-gate failures in the real worktree** (it did, fix-on vs fix-off
   identical). **Run `run_codegen` IN the worktree, not a copy** — a rsync'd tree
   breaks `test/native` stdlib resolution and shows spurious IR failures unrelated
   to any change (observed; do not be misled by it).

3. **Interaction with the DMod re-export (`:7375-7379`).** The DMod branch already
   exports `Mod.k` with the real scheme to the OUTER env after inner checking; the
   fix additionally reconciles it DURING inner checking. These are consistent (same
   `sch`), but a subtle double-bind or ordering effect is conceivable. *De-risk:*
   full `run_compiler`/`run_eval`/`run_stdlib` green (verified) plus cross-module
   qualified-call fixtures (`node_discovery`, `rpc_*`) compile unchanged.

4. **`Cap` is load-bearing for the whole capability system.** Because the fix does
   NOT touch `unify`, `cap_narrow`, `cap_subsumes`, the builtin cap schemes, or
   actor `Cap` dispatch, the capability system is structurally untouched. *De-risk:*
   the four must-preserve probes (P3 narrow, nested `Cap(IO)` passthrough,
   `is_cap_valid(id(c))` behaves identically fix-on/off, `needs` gate via a
   `needs`-declared module) — all confirmed neutral.

5. **Value restriction is NOT involved.** Probes ruled out let-generalization as
   the mechanism (a `let`-bound constructor used at two concrete types directly is
   correctly rejected). No change to generalization is proposed; do not "fix" the
   value restriction.

**Boundedness verdict (explicit, per the brief's ask):** the fix is **bounded and
small** — one guarded branch in `check_decl`, no type-representation rework, no
`unify` change, no new env field. It was implemented and passed end-to-end
validation in an instrumented compiler. Strict `Cap` unification turned out to be
**unnecessary and inappropriate** (there is no lax `Cap` unify to tighten; the
erasure is upstream of `unify`). No broad type-representation work is required.
```
