# A top-level function named like a stdlib callback parameter is called through that parameter after inlining: wrong value compiled

**Logged:** 2026-10-11. Found by the TIR verifier's pass-contract check (check 5), which
reports it on `test/native/fn_arities_shadow_poisoning.march` at `--opt 0` and `--opt 2`.
Compiled-only: the interpreter and `--no-opt` are right.

## Repro

A top-level `f` and `List.map`'s own callback parameter, also named `f`:

```march
mod Main do
  needs IO.Console
  fn f(m) do m + 1 end

  fn main(_cap_console : Cap(IO.Console)) : () do
    let xs = Cons(1, Cons(2, Cons(3, Nil)))
    println(int_to_string(List.fold_left(List.map(xs, fn x -> x * f(x)), 0, fn (a, x) -> a + x)))
    println(int_to_string(List.fold_left(List.map(xs, fn x -> f(x) + 100), 0, fn (a, x) -> a + x)))
  end
end
```

| | line 1 | line 2 |
|---|---|---|
| interpreter | `20` | `309` |
| compiled `--no-opt` | `20` | `309` |
| compiled `--opt 0` and `--opt 2` | `20` | **`409`** |

Renaming the top-level `f` to `ff` (nothing shadows anything) gives `20` and `309` at every level,
and the verifier is clean. So the name collision is the cause.

## What the verifier says

```
[tir-opt-1-inline] [contract] `f` is bound locally but is called directly after Defun;
a call through a local binding must be an indirect call
  in `List.map$List_Int$Fn_Int_Int$hspec$1__lam2_main_apply_2_main`
```

The contract is Defun's: a locally bound name that is called is a closure pointer and dispatches
through `ECallPtr`, even when a top-level function shares its name (`Defun.rw`, case B). The
violation first appears after the `Inline` pass (`tir-opt-1-inline`) and not at `tir-hof-spec` or
`tir-known-call`. The `Hof_spec` clone of `List.map` keeps its closure parameter, named `f`, and
`Inline` puts the lambda's body into the clone. That body calls the user's top-level `f` by name,
which the clone's parameter now shadows.

This is the same class as `project_defun_capture_shadowing_hof_param`, fixed for Defun's own
captures. This is the Hof_spec/Inline variant.

## Why the fixture did not catch it

`fn_arities_shadow_poisoning` guards a typechecker arity bug and prints only
`List.length(List.map(xs, fn x -> x * f(x)))`, which is `3` whatever `f` returns. The oracle lists
the fixture in `known_divergence` while this is open.

## To do

Fix the capture (rename the clone's retained parameter, or refuse to inline a body that mentions a
top-level name the call site binds locally; `Single_use_inline` has a capture guard to mirror).
Then print the mapped values in the fixture so it would catch a regression, and remove the
`known_divergence` entry.
