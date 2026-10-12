# DONE 2026-10-11: `Inline` captured a top-level name under a caller binder of the same name

Found by the verifier's Defun contract (check 5,
`specs/progress/2026-10-11-verifier-defun-contracts.md`) on
`test/native/fn_arities_shadow_poisoning.march`. A compiled-only wrong value at `--opt 0` and
`--opt 2`. The interpreter and `--no-opt` were right.

## Symptom

A top-level `f`, called from lambdas passed to `List.map`, whose own callback parameter is also `f`:

| | `x * f(x)` summed | `f(x) + 100` summed | `f(x) * 10`, first element |
|---|---|---|---|
| interpreter, `--no-opt` | `20` | `309` | `20` |
| `--opt 0` / `--opt 2` before | `20` | `409` | `200` |

Renaming the top-level function removed both the wrong value and the verifier finding.

## Cause

TIR names are not distinct local and global identifiers. `Inline.alpha_rename` freshens the
callee's own binders, but a callee's free names, its references to module functions, keep
their names. `Inline` put the lambda's apply body, `let t = f(x) in t + 100` where `f` is the
user's top-level function, into `List.map`'s `Hof_spec` clone, whose callback parameter is `f`. From
then on the name meant the parameter:

1. In the `$dps` clone a later inline resolved `f` as the top-level function by name: right by luck.
2. The non-`$dps` clone was inlined into `main`. Its parameter `f` was renamed `f_i<N>`, and the
   captured call with it, so the first element called the lambda itself: `(1 + 1 + 100) + 100`.
   That is one element too large by 100, which gives `409`.

`Single_use_inline` had a guard for exactly this, and its comment noted that `Inline.run` "has NO
capture guard at all".

## Fix (`lib/tir/inline.ml`)

`Inline.run` computes each candidate's free names once (`free_names`) and tracks the names bound at
each call site: the enclosing function's parameters, and the lets, branch binders and local
functions in scope. A call is not inlined when the two overlap, or when the callee's own name is a
local binding. This is the same lexical guard as `Single_use_inline`. Its comment explains why
lexical scope is enough even though codegen's variable map is flat per function.

## Red, then green

- **`test_codegen` `tir_verify` "Inline does not capture a top-level name":** hand-built IR with a
  top-level `f`, a `g` calling it, and an `h` whose parameter is `f` calling `g`. After
  `Inline.run`, the Defun contract must find no direct call through `h`'s `f`. It failed before the
  guard.
- **New golden `test/native/inline_capture_toplevel_name`**, built at the default and at `--opt 2`,
  prints the mapped values. Main's compiler prints `409` and `200` on it; this one matches the
  interpreter.
- **`fn_arities_shadow_poisoning`** compiles cleanly under the verifier at every level, so the
  oracle's `known_divergence` entry added with check 5 is gone again.

## What else moved

Function-by-function IR, with fresh names and labels renumbered, compared against main's compiler
over the 450 programs of `test/native`, `bench` and `test/snapshots/src`, at `--opt 0` and at
`--opt 2`. In both, one function changes in one program: `main` of
`fn_arities_shadow_poisoning`, the colliding fixture. No benchmark changes, so no benchmark was rerun.
The four programs that produce no IR fail identically under both compilers: three HTTP benches
that do not parse in the sweep copies, and one JS-only fixture.

