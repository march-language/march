# typecheck.ml decomposition (Phase 6): 14,957 → 8,272 lines

**Date:** 2026-08-26
**Plan:** `specs/plans/2026-08-19-compiler-file-decomposition.md`, Phase 6
**Branch:** `claude/typecheck-phase6`

`lib/typecheck/typecheck.ml` was the largest file in the compiler and the most
edited — 387 commits in six months. Phase 6 peels the layers *below* inference
out of it. Tasks 6.1–6.6 and 6.9 landed; the two stretch tasks (6.7 unify /
surface-type conversion, 6.8 session projection) did not, and are still open.

## Result

| File | Lines |
|---|---:|
| `lib/typecheck/typecheck.ml` (before) | 14,957 |
| `lib/typecheck/typecheck.ml` (after) | **8,272** |
| `lib/typecheck/typecheck_caps.ml` | 1,777 |
| `lib/typecheck/typecheck_builtins.ml` | 1,665 |
| `lib/typecheck/typecheck_env.ml` | 1,527 |
| `lib/typecheck/typecheck_exhaustive.ml` (+ 46-line `.mli`) | 810 |
| `lib/typecheck/typecheck_tailcall.ml` | 608 |
| `lib/typecheck/typecheck_types.ml` | 541 |

6,685 lines moved. The plan's target was ≤ 8,400 without the stretch tasks.

## The structural fact this rested on

OCaml forbids forward references at the top level, so `typecheck.ml` was
already a topologically sorted dependency graph and **every contiguous prefix
of it is downward-closed by construction**. The only thing that can bind a cut
is a `let rec … and` chain straddling it. That turned "inference is mutually
recursive, so there is no seam" into a measurable question, answered per band
by a small `dep.py` that maps every top-level name to its definition line and
lists what a candidate region references from outside itself — *after stripping
comments*, which matters: the raw greps behind the earlier "no clean seam"
reading counted doc-comment mentions of `infer_expr` as calls.

## The oracle (Task 6.1), and why two tiers

`scripts/types-oracle.sh` is new. Neither pre-existing harness pins what this
refactor could break:

- `dune build @types-check` asserts only that each `reject/` fixture's output
  *contains* one annotated substring, and that each `accept/` fixture exits 0.
  A refactor that reworded every hint and dropped every reason chain passes it.
  It is also **vacuous without `--force`** — exit 0, zero-byte log.
- `scripts/ir-oracle.sh` sees inference *results* (TIR lowering consumes
  `type_map`) but only on the accept path, and a diagnostics-only change moves
  no IR.

So: **Tier 1** hashes `--emit-core-ast` per fixture (verdict, `resolved_ty`,
`schemes`, `instantiations`, `module_caps` — the only signal at all on the
accept path), **Tier 2** stores full `--check` text (the JSON keeps only each
diagnostic's first line, dropping the excerpt, the provenance line, the reason
chain and the hint). 600 fixtures, 7,252 diagnostic lines.

**Proven RED before use**, both probes at once: appending `PROBE` to the
`int_to_string` hint moved **10 Tier-2 lines and zero Tier-1-only fixtures**;
perturbing `generalize` moved **175 Tier-1 fixtures and zero Tier-2 lines**.
Neither is visible to `@types-check`. GREEN afterwards against the same
baseline. An oracle nobody has watched fail is not evidence.

Two operational notes worth keeping: it runs under a **private `HOME` with
`.cache` pre-created** (`~/.cache/march` is shared across worktrees and its
spans carry the populating worktree's paths; and the compiler's cache-save
`mkdir` is not recursive, so `home` alone adds 177 bytes of warning per fixture
*and* re-typechecks the stdlib every invocation). And the serial loop the plan
described was tracking to ~16 minutes, so the sweep is `xargs -P 8` over a
one-fixture serial warm-up, with both manifests sorted — **~40 s warm**.

## Method: machine-checked verbatim-ness

Every motion task was proven, not asserted. The moved band was read back **out
of the destination file** (never from memory), substituted at its `include`
site in the rewritten `typecheck.ml`, and required to reproduce
`git show HEAD:…/typecheck.ml` byte-for-byte. Bands were refused unless their
boundaries sat at comment depth 0 outside string literals, computed by a real
nested-`(* *)` scanner. Trailing blank lines are content and were never
stripped.

Two reorders (`span_of_expr`, the `free_vars_*` group) move *above* their old
position, so the substitution proof does not apply; they were proven instead by
the pair "appended bytes == removed bytes" and "`git diff` shows N deletions
and **zero** additions".

## What the plan got wrong, and how it was caught

1. **Task 6.6 Step 1 is not executable as written.** It says to carry
   `free_vars_expr` / `free_vars_block` / `free_vars_pattern` down into
   `typecheck_caps.ml`. `warn_unused_params` sits between them and the
   capability band and calls `free_vars_expr`, so that move leaves the call
   unresolved (as do call sites on the far side of the band). They went into
   `typecheck_types.ml` — a module included at the *top* — which serves callers
   on both sides. The reasoning behind the plan's step (don't split a helper
   from its caller across two commits) was right; the destination was not.
2. **`cap_annots_in_expr`'s doc comment contains a blank line**, so the caps
   band starts 21 lines above the `let`, not the 3 the plan estimated. The
   comment-depth mask found it; a "walk back over the preceding comment"
   heuristic would have cut the comment in half. The plan warned about exactly
   this and was right to.
3. **`dep.py` reports zero external dependencies for a band and still misses
   some**, because it reads `typecheck.ml` alone. Once earlier bands have left,
   a later band's dependencies on *them* are invisible to it — `typecheck_caps`
   needs `cap_paths_in_surface_ty` from `Typecheck_builtins`. The compiler names
   these immediately; `dep.py` is a guide to ordering, not a completeness proof.
4. **A bare `module Ast = …` in an extracted file collides.** `include` re-exports
   submodules, so `typecheck_tailcall.ml` puts its three aliases inside a nested
   `Aliases` module reached by `open`. The later modules avoid the problem
   differently: the aliases travel with `typecheck_types.ml` and everyone else
   `open`s it.
5. **Off-by-one from reading a `sed` dump.** A leading blank line elided in
   display cost one wrong `span_of_expr` band; the *build* caught it, but the
   verbatim check did not — it proves motion fidelity, not band correctness.
   Derive boundaries from `grep -n` anchors, never from a printed excerpt.

## Aliasing, not copying

`_counter` and `_record_names` are marshalled by `bin/main.ml` into the stdlib
typecheck-env cache, and a duplicated cell there reproduces the cross-run
nondeterminism fixed on 2026-08-24. `include` re-exports the same physical
cells — asserted with a throwaway probe that mutated
`March_typecheck.Typecheck_types._counter` and read
`March_typecheck.Typecheck._counter` (before=161, after=4403), not assumed.

## Interface (Task 6.9)

`typecheck.mli` was **unmodified by every motion task** — the intended outcome,
since `include` of a module whose types *are* the definitions the interface
declares satisfies it unchanged. Task 6.9 then rewrote its docstring to say
where things now live, renumbered the surviving `§` headers contiguously
(§1–§8, replacing a scheme with gaps, a `§9b`, a `§E`, a `§16a`, and a `§16`
appearing *after* `§16a`), and added `typecheck_exhaustive.mli`: 7 of that
module's 27 definitions are its contract, so the other 20 — the pattern matrix,
its five specialisation operators, the usefulness search — stop being reachable.
The `typecheck.ml` half of that commit was proven **comments-only** by masking
every character inside a comment and diffing what remained: 5,408 code lines,
byte-identical.

No `.mli` was written for `typecheck_builtins.ml`: 39 of its 39 top-level names
are used by `typecheck.ml`, so the file would be a verbatim copy of the inferred
signature — churn with no boundary.

## Not decomposed, deliberately

- **`infer_expr … bind_lam_param`** (18 mutually recursive definitions) stays
  whole. Unlike Phase 2's `emit_expr` it does not dispatch on strings, so there
  is no hardening step to hang a split on, and its arms thread and mutate `env`
  (linearity flags, `pending_constraints`, `type_map`, the offer-refinement
  stack). Splitting means passing a callback record through every module.
- **`check_decl` and the module entry point** are consumers, not dependencies;
  a module holding them would have to compile *after* `Typecheck`, which must
  export `check_module_core`, which calls them. That is a cycle.
- **§12 linearity**, 180 lines, is smaller than the `include` glue is worth.

## Verification

Per task: the new types oracle (both tiers), `scripts/ir-oracle.sh`,
`dune build @types-check --force` (log contents, never the exit code),
`dune build @check` (17 pre-existing `forge/test` + `js` errors from a missing
optional opam dep — the baseline to tell yours apart from), and the relevant
suites. After Task 6.6, the **full** suite: 3,161 tests across 11 suites, all
passed, exit 0.

The IR oracle was **never** non-identical at any point in the phase.

One environmental note: the Phase 0 baseline run showed a single failure
(`march_let_shadowing`, `Killed: 9`, exit 137). A rerun failed a *different*
test identically on unmodified code — the documented process-sweep on this
shared box, not a regression. Later full runs were clean.

## Still open

Tasks **6.7** (`typecheck_unify.ml`, ~785 lines) and **6.8**
(`typecheck_session.ml`, ~1,094) remain. 6.7 is the highest-risk task in the
phase: its band contains two forward-hook installations
(`inject_iface_exports_ref :=`, `expand_record_ref :=`) whose `ref`s now live in
already-extracted modules, so moving it changes **module-initialisation order**.
Nothing reads either hook at init today, but the corpus never exercises
init ordering, so **no oracle in this plan would catch a regression there** —
which is why it was not attempted without budget to read both read sites and
land it the same day.
