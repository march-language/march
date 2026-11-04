First slice of §X1 of `specs/plans/2026-11-02-diagnostics-depth-plan.md`: a type mismatch inside a
constructor application or a list, tuple or record literal is reported at the part that is wrong,
not at the whole expression.

Before, `check_expr` inferred these and unified the result with the expected type at the end, so the
caret covered the whole literal and, for a list, the note said "Argument to constructor `Cons`"
(the parser desugars `[a, b]` to `Cons(a, Cons(b, Nil))`).

**Diagnostics only.** A first version pushed the expected type into the parts before checking them.
The types oracle showed that changed recorded types: a record field checked against `linear Int`
was recorded as `linear Int`, and an argument that failed to fit was recorded with the expected type
instead of its own. Only rejected programs changed, but the same path could reach well-typed code
whose expected type carries a wrapper unification ignores. So typing is left exactly as it was, and
only the report moves:

- `check_expr`'s infer-then-unify arm marks the diagnostic list first. If the check added a
  `type_mismatch` on the literal's own span, `relocate_literal_mismatch` (`lib/typecheck/typecheck.ml`)
  walks the literal read-only (`locate_literal_part`). Each part's type comes from `type_map`, and its
  expected type comes from the whole's expected type by substitution: a constructor's argument types
  through `surface_ty` with its parameters bound to the expected type's arguments, a tuple's
  components, a record's fields through `expand_record`.
- The walk descends into the first part that is `types_apart` from its expected type. That test is
  one-sided: heads plainly differ (another constructor, arity, tuple width or field set, after
  record expansion); anything undecided counts as fitting, so a correct part is never blamed.
- The diagnostic moves to the innermost such part and gains a path note ("In a list element of the
  `ports` field of a list element."), plus the expected type's origin label when the reason has a
  span. "Argument to constructor `C`." is dropped, since the path says it.
- List literals: every node of one literal shares its span, so the walk follows the tail without
  reading `type_map`, and a tail check against its own `Cons` leaves the move to the enclosing check
  of the whole literal (which knows the origin). A wrong element trips the `Cons` chain at several
  levels; those extra mismatches on the literal's span are dropped with the move.

Inference is unchanged: `scripts/oracle-base.sh types refine` against main differs only inside the
`diagnostics` arrays, once type-variable ids are renumbered by first appearance (the fresh-variable
counter's values shift).

Corpus: `test/errors/type_mismatch_25`–`30` pin the six shapes; `type_mismatch_21`'s caret narrows
to the offending element of a written `Cons(pa, Cons(pb, Nil))`.

Found on the way: a type-variable letter in a diagnostic differs between a cold and a warm typecheck
cache (`specs/todos/2026-11-03-type-var-letters-differ-cold-vs-warm-cache.md`), on main too.

Not in this slice: lambda bodies inside calls (`List.map(xs, fn x -> x + 1)` against a declared
`List(String)` still blames the whole call), `if`/`cond` branches, and the swapped pair on
`x ++ "no"`. The lambda case needs to know which argument's type forced the result's, which the walk
here can't read back from `type_map` alone.
