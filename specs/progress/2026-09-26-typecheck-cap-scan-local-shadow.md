# DONE Typecheck capability scan: a parameter named like a capability builtin was charged as the builtin

Filed 2026-09-25 from the work on
`specs/progress/2026-09-25-user-fn-named-like-builtin-symbol.md` (as
`specs/todos/2026-09-25-typecheck-cap-scan-param-named-like-builtin.md`).
Fixed 2026-09-26.

## The bug

A program with a parameter (or other local binding) named like a builtin that
needs a capability, and **no** top-level function of that name, was rejected
on both backends:

```march
mod M do
  fn go(file_read : String -> String) : String do
    file_read("x")
  end
end
```

```
function bodies in `M` call builtins that require `Cap(IO.FileRead)`, but `M`
declares no matching `needs`.
```

The call is to the parameter, so no capability is involved. The TIR-side walk
(`Cap_attrib.walk`, lib/tir/cap_attrib.ml) was made scope-aware in #659; every
AST-side scan still matched a call by bare name. A top-level fn of the same
name was already handled (`Typecheck_builtins.locally_declared_names_of`,
which masks a module's own `fn`/`let` names; the #659 rename makes the entry
file's user fn shadow the builtin in TIR too).

## The fix

One scope-aware walker, `March_ast.Calls.builtin_candidate_calls ?bound e`
(lib/ast/calls.ml): `names_and_name_spans` minus every bare-name call through
a local binding. A name is local, in its scope only, when bound by:

- a function / handler / actor-`init` parameter (seeded by the caller through
  `~bound`; `FPPat` parameters via `Calls.pattern_vars`);
- a lambda parameter (its body);
- a block `let` pattern (the rest of the block; the RHS is walked with the
  outer scope);
- a local `fn` (its own body and the rest of the block);
- a `let?` / `let*` pattern (the continuation);
- a match-arm pattern (that arm's guard and body).

Qualified calls (`M.f`) are never filtered. This is the AST twin of
`Cap_attrib.walk`'s `bound` set (fn params, `let`, case-branch vars, `letrec`
fns and params), so the typecheck error and the compiled ceiling agree.

Consumers switched from `names_and_name_spans` to it, i.e. every place a
call NAME is matched against a builtin table:

- `Typecheck_caps.check_module_needs`: Check 1b's `body_cap_uses` (DFn per
  clause with its params, DLet, actor handlers with their params), the
  per-function closure recording (`builtin_caps_of_expr` / `record_expr_owner`
  for DLet, interface defaults, impl methods, default-argument expressions;
  actor handlers; actor `init`), which feeds the `main` grant check;
- `Typecheck.check_main_grant`'s `charge_lambda` (a lambda's own builtin
  charge, seeded with the lambda's params);
- `Typecheck_modcaps.check_pure_module` / `check_deterministic_module`
  (params via the new `clause_param_names`);
- `Cap_infer.iter_cap_calls` (the "call to `file_read` requires `needs …`"
  hint), now a filter over the same walker, seeded with the clause params.

Left alone on purpose: `calls_in_expr` / `names_and_name_spans` themselves
(panic surface, refinement obligations and reference graphs have their own
resolution needs), and `literal_path_uses` (scoped-`needs` path literals),
which still matches by bare name and only matters for a local named like a
path builtin called with a string literal inside a module with a scoped
`needs`.

## Evidence

Tests in `test/test_compiler.ml`, group `cap_shadow`:

- `cap scan: locals named like a builtin shadow it`: a module with
  `file_read` bound as a parameter, a `let`, a lambda param, a match-arm
  pattern and a local fn, NO top-level `file_read`: no errors, no cap_infer
  hint.
- `cap scan: sibling's real builtin call still charged`: the same module plus a
  sibling fn calling the real `file_read`: exactly one missing-needs error
  naming `Cap(IO.FileRead)`, and exactly one cap_infer hint, on the sibling's
  line.
- `cap scan: builtin charged after shadow scope ends`: within ONE function, a
  real `file_read(...)` after a match arm and a lambda that bound `file_read`
  is still charged.
- `cap pure: local shadowing builtin is not impure`: `unix_time` as a param
  and a `let` in a `cap pure` module is fine; a sibling's real `unix_time()`
  is still the one impurity.

RED on origin/main (`1877afc22`): the accept test fails (`Expected 0,
Received 1` missing-needs errors), the sibling test fails (the hint points at
line 3, the parameter call, instead of the real call), the `cap pure` test
fails (`Expected 1, Received 3`). The scope-ends test passes on both, as it
must (it is the non-vacuousness guard). GREEN after the fix: all 13
`cap_shadow` cases pass.

CLI: the program above plus `let`/lambda/match/local-fn variants, a
`main(cap : Cap(IO.Console))` and `needs IO.Console`: origin/main exits 1 with
the error; fixed, it runs interpreted and with `--compile` (both print the
same five lines). A variant with a real `file_read` in a sibling fn is still
rejected, pointing at the sibling's call; a top-level `fn file_read` plus a
match arm binding `file_read` and a later bare `file_read(...)` runs (the
later call reaches the user fn).
