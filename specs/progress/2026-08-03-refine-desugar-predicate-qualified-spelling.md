`[P2]` **Refinement predicates are never desugared, so a qualified spelling inside one enforces nothing.**

```march
fn inner(xs : {List(Int) | List.length(_) > 0}) : Int do …   -- used to enforce NOTHING
fn inner(xs : {List(Int) | len(_) > 0}) : Int do …           -- always enforced the contract
```

**Done 2026-07-30 (Task 4, prior plan):** this started to *warn*, naming both the
spelling found and the bare measure that works, so it was no longer silent. The
remedy was independent of whether the alias was currently withdrawn, and a
record-field call (`c.cb(1)`) was deliberately not reported as a qualified call.

**Done 2026-08-03 (Task 8, this plan) — the narrow slice, shipped for real.**

The task was explicitly measurement-gated: "prototype a narrow slice, measure
the regression surface, then decide" — full predicate desugaring (running every
predicate through the general expression desugarer) was called out as the
largest, riskiest item in the whole backlog, and a well-evidenced won't-fix was
named as an acceptable outcome. The measurement came back clean, so this
shipped.

**Finding before any code changed: the brief's named anchor site was dead code
for this purpose.** The brief pointed at `Desugar.respan_ty`'s `TyRefine` arm
as the place to add a narrow rewrite. Reading the call graph first (per this
plan's standing "verify against unmodified source" discipline — this plan has
been burned by stale premises repeatedly) showed `respan_ty` is called
*exclusively* from `respan_derived_decl`, itself called *only* by `derive_impl`
(the `derive Eq/Ord/Show/…` expansion). Ordinary function signatures never pass
through it: `desugar_fn_def` never touched `param_ty` or `fn_ret_ty` at all, and
`desugar_expr`'s `ELet`/`EAnnot` arms never touched `bind_ty`/the annotation
type either. So a rewrite added inside `respan_ty`'s `TyRefine` arm, exactly as
scoped, would have had **zero effect** on the motivating example — types on
real function signatures are the *same, untouched* `A.ty` values before and
after `desugar_module` runs, regardless of what `respan_ty` does.

**What actually shipped.** A new `Desugar.desugar_ty` (`lib/desugar/desugar.ml`,
placed before `desugar_expr` since both now use it) walks the full `ty`
constructor set — mirroring `respan_ty`'s shape but respanning nothing — and at
`TyRefine` calls a new `Desugar.flatten_pred_quals`, which replicates *only*
the dotted-path flattening `desugar_expr`'s own `EField` arm already applies to
an ordinary call head (`List.length(_)` → the `EVar` `"List.length"` the
`len` alias keys on). `flatten_pred_quals` is a full structural walk of `expr`
so it finds a qualified call anywhere inside a predicate, but it does **only**
that one rewrite — no pipe desugaring, no multi-head-fn desugaring, no
conn-scope tracking, no sigil expansion, no `ELetFn`/`ELetQ` handling. `desugar_ty`
is wired into every site that carries a surface `ty` on the normal desugaring
path: `desugar_fn_def`'s param/return types (new `desugar_fn_def_tys`
pre-pass), `DType`'s variant-arg and record-field types, `ELet`'s `bind_ty`,
and `EAnnot`'s type — i.e., everywhere `Refine_check.warn_predicate_ty` itself
already recurses, which is the ground truth for "everywhere a predicate can
live."

**One real regression found and fixed before shipping, not after.** Running
the existing `qualified-predicate` alcotest suite against the prototype showed
2 failures, not 0. One (`a qualified spelling in a predicate warns`) was the
*expected* clean retirement — the warning correctly stops firing once the
qualified spelling is genuinely enforced, so the old assertion needed
rewriting to check for enforcement instead of a warning (done; see
`test/test_refinecheck.ml`'s `qualified-predicate` suite, first case). The
other (`a WITHDRAWN alias still suggests \`len\`, not the last segment`) was a
genuine degradation the brief's Step 2 explicitly told this task to catch: in
a unit that shadows `List.length`, the predicate now arrives at
`warn_predicate_expr` as a *flattened* `EVar "List.length"` rather than an
`EField` chain, so it hit the **generic** "not a measure or known predicate"
branch instead of the qualified-call branch that names `len` — a real loss of
guidance (still correctly silent/unenforced, but a worse message). Fixed by
extracting the qualified-call remedy into a shared `warn_qualified_call`
helper and routing the `EApp (EVar f, …)` branch through it whenever `f`
contains a `.` and fails `known_predicate_fn` — so a withdrawn alias is
diagnosed identically whether the spelling arrives pre-flattened (via
`EField`, e.g. `f(x).g(y)` receivers `desugar_ty` doesn't touch) or
post-flattened (the now-common case). Re-running the suite after this fix:
clean, both cases pass.

**Measurement (Step 2, the actual deliverable).**
- `test/test_refinecheck.exe -e`: 437/437 pass, 0 skip, 0 fail (same test
  count as the incoming baseline — one existing test rewritten to check the
  new behavior, no new tests added; the withdrawn-alias case already existed
  and needed no rewrite once the remedy code was unified).
- Full stdlib `--refine-report` sweep, all 112 modules, pre-fix binary vs.
  post-fix binary (file-copy revert — no `git stash`, matching this plan's
  standing discipline): **byte-identical**, because no stdlib predicate uses a
  qualified spelling (confirmed independently by grep before the sweep ran).
- Instrument confirmed non-vacuous on the motivating repro (not just the
  stdlib zero-diff, which alone would be unfalsifiable): pre-fix,
  `{List(Int) | List.length(_) > 0}` against an empty-list call records
  `0 proved, 0 violated, 1 skipped (unreflectable-predicate)`; post-fix, the
  same program records `0 proved, 1 violated, 0 skipped` — the obligation went
  from silently skipped to a genuine caught violation.
- `@types-check`: 242/242 pass (no regressions; `t136`'s exit-0 witness is
  unaffected since its call site was always non-violating — its header
  comment was rewritten to describe what actually happens now rather than
  leave a stale "enforces NOTHING" claim in an `accept/` fixture).

**Decision:** shipped. The measurement was clean and bounded exactly the way
Step 3 asked for: no new silent-enforcement-of-nothing case, the one message
regression was root-caused and fixed (not merely observed and left), and the
stdlib sweep is unchanged elsewhere.

**Still open, deliberately out of scope for this task (unaffected, pre-existing
limits — see the 2026-07-30 entry above and `specs/lang/refinement-types.md`'s
"A qualified spelling in a predicate now works" section):**
- A record **field** call inside a predicate (`{Cfg | c.cb(1) > 0}`) still
  enforces nothing and is still not reported as a qualified call —
  `flatten_pred_quals` mirrors `desugar_expr`'s own `EField` arm exactly, which
  only flattens a chain bottoming out at a bare, zero-arg, uppercase module
  `ECon`, not an arbitrary `EVar` receiver.
- A receiver that is itself a call (`f(x).g(y)`) is still not rendered as a
  path and stays silent.
- The general capability gap — running a predicate through the *rest* of the
  expression desugarer (pipes, multi-head-fn bodies, `ELetFn`/`ELetQ`, sigils,
  …) inside a predicate — remains unaddressed and, per this task's own
  measurement, is a meaningfully larger surface than the module-path case:
  every one of those constructs would need its own narrow-slice treatment (or
  a decision to run the real desugarer, with the regression surface that
  implies) if a genuine use case for them inside a `{T | …}` predicate ever
  shows up. No such use case is known today, so this is not re-opened as a
  todo — it stays a documented limit, not a gap someone is expected to close
  next.
