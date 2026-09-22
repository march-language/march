# A targeted diagnostic for `fn (a, b) -> …` used as a callback over a tuple

**Landed:** 2026-09-22

## The mistake

`fn (a, b) -> e` is a TWO-parameter (curried) lambda, not a lambda over a
tuple — `lambda_params` in `lib/parser/parser.mly` parses the parenthesized
list as a curried parameter list, and a nested pattern (`fn ((a, b)) -> e`) is
a parse error. So the natural-looking

```march
List.map(pairs, fn (k, v) -> v)     -- pairs : List((K, V))
```

is wrong, and the typechecker used to report it in one of two unhelpful ways.
In `check_expr`'s lambda-peel arm the first parameter took the WHOLE pair and
the peel then unified the callback's result variable with an arrow:

- silently accepted with a nonsense type — `fn snds(xs : List((Int, v))) :
  List(v) do List.map(xs, fn (_, w) -> w) end` makes `v := b -> b`, so callers
  get `List(b -> b)`; or
- rejected with the misleading "This type would have to be infinitely
  recursive … Did you forget to apply it" (`List.map(xs, fn (k, _) -> k)` with
  return type `List(k)`).

This is what broke `OrderedMap.keys`/`values`/`from_list` in the stdlib (fixed
earlier the same day). The `annotated_tyvar_fixed` warning only catches the
subset where a signature type variable absorbs the damage.

## The check

In the `Ast.ELam` arm of `check_expr` (`lib/typecheck/typecheck.ml`), before
the ordinary peel: when the lambda has n ≥ 2 parameters and the expected type
is `TArrow (TTuple comps, ret)` with `List.length comps = n`, AND the expected
type's arrow chain is SHORTER than n, report

```
This lambda takes 2 arguments, but it is passed where a function of ONE
argument, a 2-tuple `(Int, v)`, is expected.
`fn (_, w) -> …` is a 2-parameter (curried) lambda, not a lambda over a tuple.
To destructure the tuple, match on it:
    fn pair -> match pair do (_, w) -> … end
```

(code `curried_lambda_over_tuple`).

The arrow-depth guard is what keeps legitimately curried callbacks out of it:
`List.fold_left`'s function parameter is `b -> a -> b`, arrow depth 2 for a
2-parameter lambda, so it never fires — including when the accumulator is
itself a tuple (`fold_left(xs, (0, 0), fn (acc, x) -> …)`), which is the
shape a naive "first parameter is a 2-tuple" test would have flagged. A
callback that genuinely takes a tuple and then a second argument
(`(Int, Int) -> Int -> Int`) is likewise untouched.

Recovery binds each parameter to its corresponding tuple COMPONENT and checks
the body against the arrow's result, i.e. the interpretation the author meant,
so the one error does not cascade into a pile of follow-on mismatches.

## Tests

`test/test_compiler.ml`, group `curried_lambda_over_tuple` — six cases: the
silent case, the occurs-check case (which must also no longer report
"infinitely recursive"), a 3-tuple, and three non-firing guards (fold's
`b -> a -> b` with a tuple accumulator, the suggested `match` rewrite, and a
`(pair) -> Int -> Int` callback). The three firing cases were confirmed red
before the change; the three guards were green both before and after.

## Note for a follow-up

This adds an ERROR-level check, which under the corpus's two-repo rule
(`specs/lang/types/INDEX.md`) is mirrored by the march-lean oracle. No
`specs/lang/types/reject/` fixture was added here, so the corpus and its
counts are unchanged; if the check should be part of the Lean-checked
semantics, add a `reject/` witness and mirror it there.
