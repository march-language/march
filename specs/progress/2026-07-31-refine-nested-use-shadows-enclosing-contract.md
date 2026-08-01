`[P1]` **CLOSED: a `use` in a NESTED module shadowing an ENCLOSING contract
rejected correct code.**

This was the cardinal-sin direction — a false positive on a correct program.

```march
mod P do
  fn run(a : Int, k : {Int | k != 0}) : Int do a / k end
  mod Inner do
    use Other.{run}          -- Other.run has no refinement
    fn go() : Int do run(7, 0) end
  end
end
```

The call dispatches to the **import** (typecheck's `bind_var` gives an inner
`UseNames` priority over an enclosing definition) — confirmed end-to-end with a
two-file `MARCH_LIB_PATH` fixture, which prints the import's result. But
`resolve_call` (`lib/refinecheck/refine_check.ml`) tried the lexical
enclosing-module lookup (old step 1) *before* `use`-imported names (old
step 3), so the call was checked against `P.run`'s `k != 0` — a contract it
never touches — and wrongly rejected.

**Fix (2026-07-31).** `ctx.uses` now carries a third component, the modpath of
the module that recorded the `use` (`(exporting module dotted, selector,
scope)`), tagged at the one place it is gathered — the `A.DUse` arm of
`visit_decls`' fold, where `ctx.modpath` is already exactly the owning
module, because `visit_decl`'s `A.DMod` arm extends `modpath` before
recursing. `resolve_call`'s enclosing-module walk is now scope-aware: at each
prefix `p` of `modpath_prefixes ctx.modpath`, from innermost to outermost,
that prefix's own DEFINITION is consulted, then that SAME prefix's own
`use`-imports, before falling outward to the next prefix.

This is what makes both directions correct at once — the asymmetry that made
the naive "move the `use` step first" fix wrong:

- A nested `use` now beats an enclosing definition (the fix): the `use` is
  recorded at the inner prefix, so it is found before the walk ever reaches
  the outer prefix owning the shadowed definition.
- An outer module's `use` still loses to an inner module's own definition (the
  mirror direction, which was never broken but had to stay unbroken): the
  inner prefix's own definition is found first, before the walk ever reaches
  the outer prefix owning the `use`.

**Tests.** `test/test_refinecheck.ml`'s `resolve-precedence` suite (4 cases,
asserted by `Obligation.all`/`summary` counts rather than diagnostic presence,
since a correctly-resolved call and a silently-skipped one are both quiet):
the fix itself (no obligation raised against the enclosing contract), a
regression control (no `use` — enclosing contract still applies), the mirror-
direction control (an outer `use` does not beat an inner module's own
definition — this was already correct pre-fix and stays correct), and a
`UseSingle` control (a selector-less `use Other` binds the module, not any
bare name, so it competes with nothing).

**No `specs/lang/types/accept/` corpus witness was added.** The corpus is
single-file and `check_types.sh` runs a plain `--check` with no
`MARCH_LIB_PATH`; the compiler's real module resolution requires `use` to
name an actual sibling **file** (confirmed by direct probe: even a `use`
naming a sibling *nested* `mod` in the same file, not a separate module,
errors with `Module ... not found (looked for ... in the source directory)`,
and a file may have only one top-level `mod`). So the true shadowing scenario
— two modules with a same-named function, one refined, reached via `use` —
cannot be expressed as a single self-contained `--check` fixture the way the
`sig`/`extern`/`interface` warnings could. The behavioral pin lives entirely
in the alcotest suite (which checks the AST directly, bypassing file-based
module resolution) plus the manual two-file `MARCH_LIB_PATH` ground-truth
reproduction recorded above and in the task report.

**False-positive sweep.** Swept `stdlib/*.march` + the full
`specs/lang/types/{accept,reject}` corpus (354 files) comparing
`--refine-report`'s per-file `user code` proved/violated/skipped counts
between a pre-fix and post-fix binary (file-copy swap, never `git stash`).
See the task report for the full numbers and the sensitivity control.
