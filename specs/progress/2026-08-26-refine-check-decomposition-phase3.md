# `refine_check.ml` navigation and the parameter flood — Phase 3

**Date:** 2026-08-26
**Plan:** `specs/plans/2026-08-19-compiler-file-decomposition.md`, Phase 3
**Branch:** `claude/refine-check-phase3`

## What landed

Four commits, one per task.

| | |
|---|---|
| `refine_check.ml` | 7,416 → **7,582** lines (comments only: 122 header lines + the record's docstrings) |
| § section headers | 0 → **23**, plus a table of contents |
| `check_call` signature | **13 parameters → 8** (7 of them bundled into `call_ctx`) |
| `refine_check.mli` | new, **198 inferred vals → 17 curated** + 4 types (91% internal) |
| new script | `scripts/refine-oracle.sh` |

1. **`test: add refinement-diagnostic oracle`** — 297 fixtures, 5,638 pinned
   report lines.
2. **`docs(refinecheck): numbered section headers + TOC`** — 122 insertions, 0
   deletions.
3. **`refactor(refinecheck): bundle check_call's traversal-constant params`** —
   the phase's only semantic change.
4. **`refactor(refinecheck): add refine_check.mli`**.

## The oracle, and why it needed a third cache clear

`refine_check` emits diagnostics, not code, so `scripts/ir-oracle.sh` proves
*nothing* about it: a checker that stops checking emits byte-identical IR.
`scripts/refine-oracle.sh` sweeps `--check --refine-report` over
`test/native/*.march` + `stdlib/*.march` and pins every line.

The plan named two caches that produce vacuous green (`.march/cas/artifacts-v2`,
`.march/cas/vc`). There is a **third**, and it is not under `.march/`:
`~/.cache/march` holds the Marshal'd stdlib AST and typecheck env
(`bin/main.ml`'s `stdlib_decls` / `get_stdlib_tc_env`), keyed by stdlib content
plus compiler build id and **shared by every worktree on this box**. The
marshalled spans carry the absolute paths of whichever worktree populated the
blob, so `stdlib_prelude` diagnostics printed *another agent's directory* and the
manifest moved with nobody touching the checker — 14 phantom lines on the first
green-control run, which is exactly the noise floor a real regression would hide
in. The sweep therefore runs under a private `HOME` inside its baseline
directory, and stdlib path prefixes are normalised on top of that.

**The plan's inline draft of the script could never have run.** It repeated,
verbatim, the `${x:?…}` bug already found and fixed in `ir-oracle.sh` on
2026-08-25: bash ends the expansion at the first `}`, which is the one inside
`{baseline|check}`, so `MODE` came out as `baseline <dir>}` and every invocation
died with `unknown mode` before touching a fixture. Task 0.1's copy was
annotated `# BROKEN`; **the Task 3.1 copy was missed and stayed live for a
year-and-a-day of plan revisions.** Both the script and the plan text are fixed.

**Non-vacuity** (an oracle nobody has seen fail is not evidence):

- *RED* — two perturbations in `refine_check.ml`, one message
  (`"was NOT verified here"` → `"was NOT PROBEVERIFIED here"`) and one verdict
  (in `check_call`'s discharge, `Refine.Verified -> note Obligation.Proved` →
  `note (Obligation.Skipped Obligation.Solver_undecided)`):
  **`DIAGNOSTICS CHANGED — 1528 differing lines`, exit 1** (33 the message, the
  rest proved/skipped counts across the corpus).
- *GREEN* — probe reverted, comment-only line appended, rebuilt:
  **`REFINEMENT DIAGNOSTICS IDENTICAL (5638 lines over 297 fixtures)`, exit 0.**

Runtime ~6 min. `--refine-report` output is deterministic run to run (checked
before recording anything).

## Section headers: how "comments only" was proven

The inserter computes a real in-comment character mask (nested OCaml comments
*and* string literals) rather than walking back over lines that "look like"
comments — the documented trap is that **a doc comment containing a blank line**
defeats naive walk-back and makes an insertion land inside a comment, swallowing
half of it. It then refuses to write unless the source with every comment
stripped is byte-identical before and after. Result: 122 insertions, 0
deletions.

23 sections, not the plan's "~12": at 7,400 lines the finer grain is what makes
`grep -n '§'` a usable index. `check_call` is §15; its postcondition
counterparts are §16–§18.

## `check_call`: what is context and what is a parameter

Traced through all three call sites (`visit`'s two `EApp` arms and
`check_let_annotation`), not one. Seven parameters are the environment an
obligation is discharged *in* — `root`, `errctx`, `postcond`, `path`, `lets`,
`sc`, `re` — and became a `call_ctx` record with a docstring per field, which is
the documentation this 1,361-line function has never had. What differs per
obligation stays explicit: `~span`/`~callee` (which call), `sg`/`args` (its
signature and actuals), `rp` (which refined parameter), and the
`?subject`/`?verdict_out` that only the `let`-annotation caller sets.

**Deviation from the plan's field list.** The plan put `rp` in the record and
left `path` out. Measurement says the opposite: `rp` varies per iteration of
`List.iter … sg.refined` at both `visit` sites, while `path` is threaded exactly
like `lets`/`sc`/`re` and is shadowed with them at the `let`-annotation site.
Keeping the three fact channels together in one record is also what makes their
shared retirement discipline statable in one place.

The record is destructured to the body's existing names on the function's first
line, so the 1,361-line body is untouched: this is a signature change, not a
rewrite. At the two `visit` sites the record is now built once per call node
instead of a 13-argument list being respelled per refined parameter.

No `CHANGELOG.md` bullet. The plan predicted Phase 3's hardening would change
diagnostics; the oracle says it does not, and CLAUDE.md's rule is that a
refactor with no observable effect gets no entry.

## `.mli`: 198 → 17

`check_module` is the entry point — 52 of the qualified references in the tree
are to it. The other 16 exist because `precond_infer`, `postcond_infer`,
`division_safety` and `--check-migration` re-use pieces of the machinery it sets
up; several of them *require* `check_module` to have run first, because they
read registration globals it populates, and the interface now says so.

`dune build @check` is the oracle here, as in PR #354: `open` does not
re-export, so a grep for `Refine_check.<name>` cannot see the `RC.`/`Rc.` alias
uses in `precond_infer`, `postcond_infer` and `bin/main.ml`. 17 pre-existing
`forge/test` + `js` errors (missing optional opam dep) before and after, none
new.

### Finding: three values have no caller at all

`smt_sort_of_marker`, `expr_binds_name` and `register_types_for_check` are dead
in and out of the module. They are declared under a "Not API" heading because
hiding them is an `unused-value-declaration` error under warnings-as-errors —
the same accommodation `lower.ml` needed for three re-exports in PR #354.

`register_types_for_check` is the interesting one. Its own docstring says
`--check-migration` calls it "to prime the type tables", and it is the only
thing that *clears* those tables first, "to avoid stale accumulation from prior
calls". `--check-migration` does not call it: `bin/main.ml`'s `Rc` block calls
`register_adt_names` and `register_field_sorts` directly, so the clearing never
happens. Whether that matters is a behavioural question about migration
checking, deliberately not answered in an interface-only commit.

## Verification

Run after **every** task:

- `scripts/refine-oracle.sh check` — `REFINEMENT DIAGNOSTICS IDENTICAL (5638
  lines over 297 fixtures)`, exit 0, three times (3.2, 3.3, 3.4). Never
  anything else.
- `scripts/ir-oracle.sh check` — `IR IDENTICAL across 240 programs`, exit 0,
  three times. `refine_check` is a checker; a changed byte of IR would have
  been a real finding.
- `dune build --root . bin/main.exe`, exit 0.
- Suite after 3.3 and after 3.4: **2,763 tests, seven runners, every one exit
  0** — `run_compiler` 936, `run_codegen` 593, `run_stdlib` 878, `run_eval` 273,
  `test_stdlib_march` 61, `test_jit` 22 (with `MARCH_BIN` set, else it skips
  silently), plus `run_snapshots` 33.

## Still open

- `check_call` is still 1,361 lines. Phase 3 was scoped to its signature and to
  navigation; carving its body is a separate job.
- The three dead values above: delete, or make `--check-migration` use
  `register_types_for_check` as its docstring intends.
- `refine_check.ml` has no sibling modules yet. §5 (ADT/record sorts and the
  preamble builders, ~600 lines) and §20 (refinement-placement warnings, ~380)
  are self-contained enough to move if this file needs to shrink.
