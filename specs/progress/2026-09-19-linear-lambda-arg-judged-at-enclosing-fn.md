# FIXED 2026-09-19: a lambda's pending linear parameter is judged again at the enclosing function's close

## Cause

A lambda parameter whose type is not yet known is bound as a *pending* entry,
and `judge_pending` decides it at the lambda's close. In `ap2(fn s -> 0, S1(1))`
the lambda is checked before the argument that fixes `a` to `S1`, so at that
close `s` still had an unbound type. `judge_pending` treated it as polymorphic
and dropped the entry; nothing looked at it again once the call was solved.

## Fix

`lib/typecheck/typecheck.ml`:

- `judge_pending` takes `?defer` (default true). A pending entry that is still
  undecided *and whose type still contains an unbound variable* is pushed onto
  the `deferred_pending` collector instead of being dropped.
- `with_deferred_pending` installs a fresh collector around each body with no
  enclosing lambda scope: a named function's body (`check_fn`), an actor
  handler's body, a `test`/`setup`/`setup_all` body, and a top-level `let`
  (through the unification with its pattern, since an annotation such as
  `let m : LinearMap(S1, Int) = ...` may be what fixes the type). It judges
  what was collected with `~defer:false` once that body is solved. By then the later
  argument has fixed the type, so the entry gets exactly the checks an
  annotated parameter would: never used, used more than once, consumed on only
  some branches.
- The function's and the handler's own parameter judgements pass
  `~defer:false`. A type still open at a function's own close really is
  polymorphic.

The first version installed the collector only for named functions and actor
handlers. Code review found the same shape still accepted in a `test` body, and
the other declaration bodies were covered in the same change
(`reject/t268_linear_lambda_arg_in_test`).

## Verification

- `specs/lang/types/reject/t262_linear_lambda_arg_before_value`: accepted by
  the pre-fix compiler, now rejected with "The linear value `s` was never used".
  `accept/t265_linear_lambda_arg_consumed` is the consuming counterpart; it
  passes both before and after.
- `reject/t254` (`LinearMap.empty(fn a -> fn b -> false)` under a
  `LinearMap(S1, Int)` annotation) now also reports the dropped `a`, as that
  fixture's comment anticipated.
- `march --check` over all 124 stdlib modules: exit codes identical and output
  byte-identical, pre-fix versus post-fix compiler.

---

The original filing follows.

# `[P2]` Linearity: a lambda argument checked before its parameter's type is known can drop a linear value

Filed 2026-09-18 during the LinearMap work
([[2026-09-18-linear-map]]). A soundness hole; not touched by that change.

## Symptom

```march
always_linear type S1 = S1(Int)
fn ap2(f : a -> Int, linear x : a) : Int do f(x) end
...
ap2(fn s -> 0, S1(1))        -- accepted: the lambda drops S1(1)
```

`ap2(S1(1)` in the other order (value first, then the lambda) is rejected ("The
linear value `s` was never used"), because `a` is already `S1` when the lambda is
checked. With the lambda first, `s`'s type is an unbound variable when the lambda
body is checked, so it is bound as a pending entry, and the pending entry is not
reported once the later argument fixes `a` to `S1`.

The same shape appeared in `reject/t254`: `LinearMap.empty(fn a -> fn b -> false)`
under a `let m : LinearMap(S1, Int)` annotation reports nothing about `a` and `b`,
while `let f : S1 -> S1 -> Bool = fn a -> fn b -> false` does.

`LinearMap.drain(m, acc, f)` is not affected in practice: the map comes first, so
`v` is known when the callback is checked (`reject/t252`).

## Where to look

`judge_pending` runs at the lambda's scope close, while the parameter's type is still
unbound, so "One still unresolved is polymorphic, and is left alone." A pending entry
of a lambda passed as an argument needs judging again once the enclosing call is
solved (or at the enclosing function's close), as unannotated `fn` parameters are.

## Tests

Reject: `ap2(fn s -> 0, S1(1))`. Accept: the same with `fn s -> sink(s)`.
