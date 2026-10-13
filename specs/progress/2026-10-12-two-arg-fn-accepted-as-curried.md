# DONE 2026-10-12: A two-argument function typechecks where a curried one is expected

**Found** 2026-10-12 while writing a leak probe for the sanitizer sweep.
**Fixed** 2026-10-12 (branch `group-s/curried-fn-soundness`). See "Resolution" at the end.

```march
mod Cur do
  needs IO.Console

  pfn ap2(f, x, y) do
    let g = f(x)
    g(y)
  end
  pfn add(a : Int, b : Int) : Int do a + b end

  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(ap2(add, 1, 2)))
  end
end
```

`march --check` accepts it. The interpreter then fails with
`arity mismatch: expected 2 args, got 1` at `f(x)`, and the compiled binary
dies with `march: fatal SIGSEGV si_code=2 addr=0x13` (it calls the two-argument
`add` through the one-argument closure ABI, then calls the returned garbage).

The realistic way to hit it is the stdlib's curried comparators:
`Map.insert(m, k, v, cmp)` documents `cmp : k -> k -> Bool` and calls
`cmp(a)` then the result (`Map.cmp_eq`), but passing
`pfn lt(a : Float, b : Float) : Bool do a < b end` typechecks and crashes the
compiled program on the first insert.

So `a -> (b -> c)` and the two-parameter function type unify somewhere in
`lib/typecheck/typecheck.ml`. Which type a `pfn f(a, b)` gets, and how an
annotation `A -> B -> C` parses (`(A, B) -> R` is a one-TUPLE-argument type),
needs pinning down before a fix; it is a typechecker soundness question, not a
codegen one.

## Resolution

**Root cause.** There is no n-ary arrow type. `fn add(a, b)` is typed
`Int -> Int -> Int`, the same `TArrow` chain as a curried
`fn a -> fn b -> a + b`, and `infer_app` consumes the chain one argument at a
time whatever the call's argument count. The grammar has no multi-argument
arrow either (`specs/lang/grammar.md` §7.2), so at the TYPE level the two are
the same type by design, and annotations like `b -> a -> b` (fold's callback,
applied `f(acc, x)`) and `k -> k -> Bool` (Map's comparator, applied
`cmp(a)` then the result) are spelled identically while meaning different
runtime arities. At RUNTIME there is no partial application: a closure is
called with exactly the call site's arguments, and closures carry no arity
(no generic over/under-application path in either backend).

**Why not a representation fix.** Splitting `TArrow` by arity would need new
surface syntax for one of the two meanings and touch every arrow-walking site
(typecheck, the 663 builtin signatures, TIR `convert_ty`, refinements, LSP);
an arity-adapting call path (OCaml's `caml_applyN`) would change the closure
ABI everywhere, including HCR. Both are language/ABI redesigns, out of scope.

**What landed: a callback call-arity check**, in the style of the existing
`fn_arities` call-site arity check.

- `lib/typecheck/typecheck_callarity.ml` computes, per module and
  syntactically, how many arguments each fn's body applies each parameter to:
  directly (`f(x)` ⇒ 1), or by passing it to another known fn's parameter
  whose call-arity is known (`cmp_eq(cmp, a, b)`, including from inside a
  lambda), iterated to a fixpoint. Mixed counts, zero-argument calls and
  parameters rebound in scope give no entry. The walk is
  `March_ast.Calls.free_app_sites` (scope-aware, same rules as
  `builtin_candidate_calls`).
- Entries live in `env.param_call_arities`, keyed like `fn_arities` (bare) and
  `qual_fn_arities` (exported `Mod.fn`), and are only consulted when the
  matching arity entry has the same definition span, so a shadowing local
  never inherits one. `check_decls_with_callarity` recomputes the module's
  table after each nested/sibling `DMod` is checked, so a fn that hands its
  parameter to `Map.insert` sees `Map.insert`'s entry.
- At a call of a known fn, an argument that is a module fn by name, a
  let-bound lambda, or a lambda literal, of known arity n ≥ 1, passed to a
  parameter applied with m ≠ n arguments, is the error
  `callback_arity_mismatch`: "`add` takes 2 arguments, but `ap2` calls its
  parameter `f` with 1 argument", with a `fn a -> fn b -> add(a, b)` wrapper
  suggested in the curried direction.

Both directions are caught (a 2-argument fn where the callee curries, and a
curried lambda where the callee applies two arguments at once). Not caught:
function values that flow through records, lists or unknown higher-order
builtins, and a parameter whose only use is to be returned or stored. Those
still fail at runtime as before; a full fix needs one of the redesigns above.

**Fallout.** No stdlib file (the stdlib ratchet is unchanged) and no test
suite program. One corpus fixture, `specs/lang/types/accept/t298_pmap_captures_immutable_map`,
passed a two-argument `int_cmp` to `Map.insert`/`Map.get`; it only ever ran
under `--check` (a second insert would have crashed it), and now uses a curried
comparator. A `--check` sweep of every `.march` file under `specs/`,
`examples/`, `docs/`, `bench/`, `test/` and `stdlib/` mentioning a comparator,
fold, sort or `Map.` found nothing else.

**Tests.** `specs/lang/types/reject/t320_two_arg_fn_passed_as_curried`,
`accept/t321_curried_and_two_arg_callbacks` (run-witnessed interpreted and
compiled), and the `callback_call_arity` group in `test/test_compiler.ml`.

## Fixed 2026-10-13: the stale todo, and two narrow extensions

**Fixed by #948.** The original repro (`ap2(add, 1, 2)`) and `Map.insert` with
a two-argument comparator were already rejected on main by #948 (this file's
Resolution above). The open todo `specs/todos/2026-10-12-two-arg-fn-accepted-as-curried.md`
was a duplicate filed on a parallel branch (6c3111a6f) and never removed; it is
deleted in this commit. Re-checked on origin/main 3d2925fce: rejected are a
named 2-arg fn / 2-arg lambda passed where the callee curries, a curried
lambda passed to `List.fold_left` / `Range.reduce` / a local `f(x, y)` callee,
and the same through a helper (`Map.insert`).

**Still accepted on main, now rejected** (each `--check` exit 0, then
`arity mismatch` interpreted and `SIGSEGV si_code=2 addr=0x13` compiled):

- `let h = add` then `let g = h(1)`; `g(2)`: an alias of a known fn called
  with the wrong count. Now `arity_mismatch`: "`h` is bound to `add`, which
  takes 2 arguments, but is called with 1 argument", labelled at the binding;
  an under-applied call's result is `TError`, so no "not a function" cascade.
- `ap2(h, 1, 2)` with that alias, and `let g = f` (`f` a curried lambda)
  passed to `List.fold_left`: an alias passed as a callback. Now
  `callback_arity_mismatch`.
- `let ap = fn (f, x, y) -> let g = f(x) … ; ap(add, 1, 2)`: a let-bound
  lambda as the CALLEE. Its parameters' call-arities are computed from its
  body (`Typecheck_callarity.lambda`, same counting as module fns, callees
  resolved in the scope at the `let`), so it is checked like a module fn.

**How.** New env field `fn_aliases` (name -> arity, aliased spelling), set at
`let name = f` for `f` a module fn or qualified export of arity >= 1 (or
another alias), cleared by `bind_var`; `let g = f` with `f` a let-bound lambda
copies `f`'s `lambda_arities` and `param_call_arities` entries. One resolver,
`callee_call_arities`, now finds a callee's parameter call-arities for a
module fn, a qualified export, a let-bound lambda (entry keyed by the let name
at the lambda's span) or an alias. Also fixed in passing: a fn's own parameter
used as a callee is never resolved to a like-named module fn when counting.

**Not covered (unchanged, owner decision pending):** a function returned from
a function (`ap2(pick(), 1, 2)`, `pfn pick() do add end`) or carried in a
list/record/`Option`; see `specs/todos/2026-10-12-function-arity-not-in-types.md`.

**Corpus.** `--check` of all 1484 `.march` files under `test/native`,
`examples`, `test/stdlib`, `specs/lang`, `bench`, `test/errors`, `docs`, with
origin/main's compiler and with this one (private HOME): identical exit codes
and diagnostic codes (890 accept / 594 reject on both). Stdlib ratchet
unchanged (`stdlib_known_internal_errors` still empty).

**Tests.** Four cases in `test/test_compiler.ml` group `callback_call_arity`
(alias called wrong, alias as callback, let-bound lambda callee, matching
shapes accepted): three FAIL on origin/main, all pass here.
`specs/lang/types/reject/t322_fn_alias_called_curried` (accepted on
origin/main, rejected here).
