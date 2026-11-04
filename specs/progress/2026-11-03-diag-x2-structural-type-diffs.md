§X2 of `specs/plans/2026-11-02-diagnostics-depth-plan.md` (logged 2026-11-02 as
`[P2]` structural type diffs): a large type mismatch is rendered as a diff.

Before, `unify` recursed into type arguments, tuple components, record fields and function
types, and reported the first pair whose heads disagreed. The message then named only that
inner pair: `take(r)` with `r : Result(List(Int), String)` against `Result(List(String), String)`
said "expected `String` but got `Int`", and the hint for that pair ("Use `int_to_string(x)`")
named the wrong value.

**Diagnostics only.** `unify` is now an entry over a walk, `unify_at`
(`lib/typecheck/typecheck_unify.ml`). The walk unifies exactly as before, in the same order and
with the same bindings, but a plain mismatch below the root is collected rather than reported.
An occurs failure and a capability-for-capability pair (§F1) keep their own reports at the part.
When the walk collected something, the entry reports once on the whole pair:

- `type_diffs` walks the two types read-only after unification and returns each part where the
  heads plainly differ, with its path (`DArg`, `DComp`, `DField`, `DParam`, `DResult`). It is
  one-sided like `Typecheck.types_apart`: a type variable, an error or a channel never differs.
- `pp_ty_diff` prints a type as `pp_ty` does, except that a part with a difference below it is
  spelled out (a record by its fields, so a caret can point into a recovered record name), and,
  when either type is longer than 50 characters, a part with none prints as `…`. It returns the
  column and width of each differing part (columns, since `…` is three bytes).
- `diff_mismatch_message` builds the headline from the two prints and one note: "The types
  differ here:", the provided type, and a caret line per difference (at most three, then "(and N
  more)") labelled with the required part. A single record-vs-record difference keeps the
  field explanation (`record_fields_note`, extracted from `report_type_mismatch`).
- `report_type_mismatch` takes the diff as `?diff`, replacing the headline and the argument or
  field note, and drops the frequently-confused-pair hints, which are about the roots or would
  name the wrong value. When no part plainly differs any more, the first collected pair is
  reported as before.

X1's literal relocation (`relocate_literal_mismatch`) now rewrites the headline to the part's own
pair (`locate_literal_part` returns the part's type and its expected type), with a diff when the
part differs further in and the pair's hint (`common_mismatch_hint`, extracted) when it doesn't.

The record-expansion hook's one dereference moved into `expand_nominal_record`, beside the hook,
which `unify` and the diff call; the file header's initialisation-order invariant says so.

Corpus: `test/errors/type_mismatch_31` (a long record, elided), `_32` (`Result(List(_))`), `_33`
(a function type), `_34` (two differences, two carets). `pure_violation_1`, `type_mismatch_10`,
`_17`, `_21` and `_23` now show the whole pair with a diff; `_17` and `_21`'s EXPECT lines follow.
`type_mismatch_10` (an impl method returning `Int` for `String`) loses the `int_to_string` hint.

Not done: printing an actor's pid by its actor name rather than its state record
(`Pid({ s : String })`, §F2), and colour in the caret line.
