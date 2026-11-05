Third and last slice of §X1 of `specs/plans/2026-11-02-diagnostics-depth-plan.md` (slices 1 and 2:
`specs/progress/2026-11-03-diag-x1-blame-literals-and-ctors.md`,
`specs/progress/2026-11-04-diag-x1-lambda-bodies.md`): an `if` or `match do` checked against a known
type blames the branch that disagrees with it, and an operand of `++` is named as one.

**Branches.** `if n >= 0 do "positive" else -1 end` in a function returning `Int` used to give two
errors: the whole `if` against the return type, then `-1` for not matching `"positive"`, which
blamed the branch that was right. Now it gives one, on `"positive"`: "expected `Int` but got
`String`.", "In the `if` branch.", with the return type's origin label.

**Diagnostics only**, like slices 1 and 2. `check_expr`'s infer-then-unify arm calls
`relocate_branch_mismatch` (`lib/typecheck/typecheck.ml`) last. It collects the value positions of
the `if`/`match do` (`branch_leaves`: a block's last expression, through nested `if`/`match do` in
tail position), reads each one's type from `type_map`, and finds those `types_apart` from the
expected type. It acts only when every leaf has a recorded type, some leaf is apart, and either
another leaf fits or the branches also disagreed among themselves. Then it drops the mismatch on the
whole expression and the branch-agreement mismatches on the leaves, and reports each apart leaf
against the expected type with the original reason (`report_pair`, X2's diff when the pair differs
below the root). A literal leaf narrows through slice 1's `locate_literal_part` ("In the `port`
field of the `else` branch."). Branches that all agree on the wrong type (`if b do "yes" else "no"
end` in an `Int` function) keep the error on the whole `if`: the `if` is the wrong part.

Paths: "the `if` branch", "the `else` branch", "an `else if` branch" (an `else if` chain reads as
one `if`, not an `else` of an `else`), "the second arm" of a `match do`.

Two smaller fixes on the way:
- The `if` agreement check (no known type) reports at the branches' last expressions, not the whole
  block.
- A `match do` arm that disagrees with the first arm, with no known type, was reported on the whole
  `match do` with the types swapped ("expected `String` but got `Int`" for a `String` arm after an
  `Int` one). The unification is unchanged (its order decides which variable links to which); the
  report moves to the arm, with the first arm as the origin and the types the right way round.

**Operator operands.** `x ++ "no"` with `x : Int` in an `Int` function keeps its two errors (§X3
judged them independent), but they no longer read as a swapped pair of generic call errors:
- The operand error comes first. `Errors.sorted` (`lib/errors/errors.ml`) now orders two reports
  that start at the same place narrower first, so the cause precedes the whole expression's
  mismatch. Only `type_mismatch_2` moved in the corpus.
- An operand of a binary operator (`++`, `+`, `-`, `*`, `/`, `%`, the float operators, comparisons,
  `==`, `!=`, `&&`, `||`) is named as one: "This is the left side of `++`, which joins two
  `String`s.", "This is the right side of `+`, and both sides of `+` must have the same type.",
  "This is the left side of `&&`, which takes two `Bool`s.", never "argument #1 of a function
  call". The origin label goes on the other operand when that one is known to have the expected
  type: always for an operator whose sides share a type variable (the left side decided it; read
  before the left side binds it), and for a fixed-type operator when the other side is a literal
  of that type or was already inferred as one (`"no"` in `x ++ "no"`; nothing in `1 ++ 2`).
  `operand_reason` builds it; `infer_app`'s `payload` is now a function of the argument index, so
  the protocol-step payload reason and operands share it.
- The result error adds "`++` joins two `String`s, so its result is a `String`."
(`<>` is not a March operator; there is nothing to do for it.)

Corpus: `test/errors/type_mismatch_43` (`if` branch), `_44` (annotated `let`), `_45` (`else if`
chain, block), `_46` (`match do` arm against the return type), `_47` (`match do` with no known
type), `_48` (guard: both branches agree), `_49` (record literal in a branch), `_50` (`+`).
`type_mismatch_1`, `_2`, `_22` and `cap_grant_17` show the operand wording; `_2` the order.

Not done (no open item; small): an `if` whose expected type is a type variable bound later, and a
`match` with patterns (already checked per arm in check mode).
