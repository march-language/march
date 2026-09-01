# Self-referential record type: infinite loop, and a misleading mismatch message

Two distinct bugs, both triggered by using a self-referential record type
(`type Tree = { left : Option(Tree), ... }`) without an explicit type
annotation — most commonly a multi-head function whose sole parameter is a
record pattern destructuring one:

```march
mod T do
  type Tr = { left : Option(Tr), value : Int }

  fn f({ left: None, value: v}) : Int do v end
  fn f({ left: l, value: v }) : Int do
    match l do
      Some(lt) -> f(lt)
      None -> 0
    end
  end
end
```

## Bug 1 — infinite loop (100% CPU, compiler never returns)

`lib/typecheck/typecheck_unify.ml`'s `surface_ty` (record-expansion branch)
and `expand_record` both recursively re-expand a named record's field types
with no recursion guard. Expanding `Tr`'s fields requires expanding
`Option(Tr)`'s argument `Tr`, which re-enters the same branch — forever.
Confirmed via `sample` on the hung process: thousands of stacked
`surface_ty`/`expand_record` frames.

Reproduces from an explicit annotation alone too (`fn f(t : Tr) : Int do
t.value end`), with zero calls in the body — it's about registering/using
the type at all, not about recursion in the source program. Doesn't trigger
for a variant type (`Leaf | Node(...)`), since variants aren't registered in
`env.records` and never enter this branch.

**Fix:** a shared `expanding_records : StringSet.t ref`, checked at the top
of both expansion branches. Already-expanding a name → stop and return the
plain nominal `TCon(name, args)` instead of unfolding again. `unify`'s
existing lazy `TCon`<->`TRecord` reconciliation (`expand_record_ref`, used
on demand wherever a field is actually accessed) already handles one level
of expansion correctly — this just stops `surface_ty`/`expand_record` from
eagerly unfolding past what any caller needs.

## Bug 2 — "expected `Tree` but got `a`", wrong location, no explanation

Even where bug 1 doesn't hang (message differs by exact repro shape), the
resulting diagnostic points at the wrong clause and names an internal,
unresolved type-variable (`a`, `y55`, …) as if it were a real mismatched
type — nothing in the message says why, or how to fix it.

Root cause: an unannotated record-pattern parameter falls back to "closed
synthesis" (`typecheck.ml`'s `infer_pattern`, `PatRecord` case, `expected =
None` branch) — it infers each field's type structurally from the
sub-pattern instead of deferring to a real declared type. For a
self-referential field this produces a type equation the field's own
variable can never satisfy without containing itself — a genuine
occurs-check violation, not an ordinary mismatch. `unify`'s occurs-check
branch reported it through the same generic `report_mismatch` used for
everything else, with no indication that "the type would have to be
infinite" is what actually happened.

**Fix:** `report_mismatch` gets an `~occurs_violation` flag, set by `unify`'s
occurs-check branch; when set, the diagnostic leads with an explanation
("this type would have to be infinitely recursive... add an explicit type
annotation") ahead of the usual expected/got line, rather than leaving the
reader to decode a bare internal variable name.

The underlying constraint doesn't go away — March still can't infer a
self-referential record's type from an unannotated destructuring pattern
alone — but the message now says so and points at the fix (annotate the
parameter with the type's declared name), confirmed working:
`fn f(t : Tr) : Int do match t do ... end end` compiles cleanly.

## Evidence

- Both repros (multi-head + record pattern; explicit annotation alone) no
  longer hang, confirmed with a 10s `perl -e 'alarm N; exec ...'` wrapper
  (no `timeout` binary on this Mac).
- `scripts/run-tests.sh` (full suite, including Slow) — all suites pass.
- A compiled self-referential-record program (`leaf_value`, reading a field
  through an `Option`-wrapped self-reference) still compiles and runs
  correctly after the `expanding_records` guard — confirms codegen's own
  type handling (shared machinery) wasn't narrowed.
