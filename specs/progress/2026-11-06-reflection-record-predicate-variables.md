# Record-typed variables in refinement predicates (2026-11-06)

The record half of "A tuple- or record-typed variable in a predicate" in
`specs/todos/2026-10-31-reflection-encoder-gaps.md`. The tuple half is a separate branch
(`claude/stdlib-lemma-sweep-s3`); the two touch the same files and merge by hand.

## The gap, measured first

Functions over records have reflected since
`specs/progress/2026-11-06-reflection-float-string-records-tuples.md`, and some predicates over a
record VARIABLE already proved (`swp(swp(p)) == p`, `px(bump(p)) == px(p) + 10`): stage 2
re-sorts `p` from the reflected call's signature. Eight shapes did not:

| | Shape | Before | Now |
|---|---|---|---|
| G1 | `need_pt(p, p)` against `b : {Pt \| _ == a}` | `sort-conflict` | proved |
| G2 | `need_pt(p, swp(swp(p)))` | `unreflectable-subject` | proved |
| G3 | `need_x(bump(p))` against `q : {Pt \| _.x > 0}`, `p : {Pt \| _.x >= 0}` | `unreflectable-subject` | proved |
| G4 | `need_gt(p, p.x + 1)` against `n : {Int \| _ > p.x}` | `unreflectable-predicate` | proved |
| G5 | `fn r1(p : Pt) : {Int \| _ == p.x} do p.x end`, and `px(p)` for `p.x + p.y` | `unreflectable-subject` | proved |
| G6 | `{Pt \| _.x == p.y}` returning `swp(p)`; `{Pt \| _ == swp(swp(p))}` returning `p` | skip | proved |
| G7 | `@[lemma] fn l_px(p : Pt) : {Unit \| px(p) == p.x + p.y}` | `unreflectable-predicate` | admitted |
| G8 | `swp({ x: n, y: 1 }) == { x: 1, y: n }`, printed `swp(<predicate>) == <predicate>` | `unreflectable-predicate` | admitted, printed as written |

## What changed

- **Postconditions (`refine_post.ml`).** A record-typed parameter is declared at its record sort
  in `scalar_env` (`Refine_scope.record_sort_of_param_ty`), not `Int`. A field resolver over such
  names (`env_field_resolver`) sits under the refined-scope one, and the goal falls back to them
  when its own binder is not the receiver. The datatype preamble is attached when one is used
  (G5, G6).
- **Call sites (`refine_call.ml`).**
  - `record_self` became `record_term sort e`, with a stage-2 arm: a reflected call returning
    the record is its logic symbol, record arguments through `record_term`, scalar ones through
    `reflect_scalar` (G2, G3).
  - Another callee parameter declared as a record translates its actual through `record_term`
    in both stages, not the scalar path (G1), and the goal's field resolver reads its fields
    (G4).
  - A caller-scope record variable in the goal is its constant at the record sort, the one
    `path_resolve_field` projects from, instead of being dropped; the goal's field resolver
    falls back to the same caller-scope projection (G7: a lemma's theorem names the lemma's own
    parameters as caller-scope names).
- **Predicates (`refine_scope.ml`).** A record literal with no parameter to type it is the one
  record whose field names are exactly these, when exactly one unambiguous, non-parametric record
  declares that set; otherwise it declines (G8). `pred_str` prints a record literal as written.

## Rulings

1. **A literal typed by field names alone.** March records are structural, so `{ x: 1, y: n }` in
   a predicate has no declared type to read. The literal is taken as the unique record with that
   field set, and declines when two records share it (a REJECT case pins that). A mismatched
   field sort is caught by the query's well-sortedness check like any other term.
2. **The violation label keeps its old text.** With record literals printable, the label "this
   argument must satisfy" substituted the literal into `v.port >= 1` and read
   `{ port: 0 }.port >= 1` (`cap_grant_8`). A rendering that reads a field off a literal is
   refused like `<predicate>` was, so the parameter-named form (`c.port >= 1`) is shown, as
   before.
3. **A field read on a call result (`swp(p).x`) does not parse in a predicate.** Not attempted
   here; it is a parser question, not an encoder one.

## Verification

| Check | Result |
|---|---|
| New group `reflect-record-vars`: one case per shape above, plus REJECT controls (a false lemma over fields, a different reflected record, `_ > p.x` with `p.x`, `{Int \| _ == p.y}` returning `p.x`, `{Pt \| _.x == p.x}` returning `swp(p)`, a false literal theorem, an ambiguous literal) | 18/18; the positive cases were RED before, the REJECT controls passed before and after |
| refine-oracle vs main | IDENTICAL (8149 lines over 574 fixtures) |
| `scripts/run-tests.sh refinecheck` (full, incl. `audit-baseline`) | passes |
| `run_errors` (golden diagnostics) | 414/414 after ruling 2 (`cap_grant_8` failed before it) |
| `@types-check` conformance corpus | 492 passed, 0 failed |
