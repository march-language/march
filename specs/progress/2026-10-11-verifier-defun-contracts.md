# DONE 2026-10-11: A1 check 5, Defun's pass contracts

Observability plan section 6, check 5, first slice. Check 3's follow-up list
(`specs/todos/2026-10-08-verifier-a4-followups.md`) named checks 4 and 5.

## What landed

`Tir_verify` checks two of Defun's documented postconditions at every stage from
`tir-defun` on (`post_defun_stage`: every `tir-*` stage except lower, trmc, mono
and fusion), tagged `[contract]`:

- **No lambda creation site.** `ELetRec([f], EAtom f)` is replaced by an allocation of the
  closure struct (`Defun.rw`, case A).
- **No direct call through a local binding.** A parameter, let or branch binder that is
  called is a closure pointer and dispatches through `ECallPtr`, even when a top-level
  function shares its name (`Defun.rw`, case B).

Two of the plan's contracts are not checked, and why:
- "Post-mono: no polymorphic `fn_def`" is already check 2's named-type-variable rule.
- "Post-join-points: every `$jp` defined once" is not an invariant. Inlining the same body
  twice repeats a name inside one function, and scoping makes that harmless.
- "Post-escape: `EStackAlloc` values do not escape" needs the escape analysis itself, which is a
  transform, not a check. It stays open with check 4.

## What it found

The second contract fires on one fixture, `test/native/fn_arities_shadow_poisoning.march`,
at `--opt 0` and `--opt 2` and not at `--no-opt`. It is a real compiled-only miscompile. A
top-level `f` shadowed by `List.map`'s own callback parameter `f` after `Inline` is called
through the parameter, so a value-printing variant prints `409` where the interpreter
prints `309`. The fixture prints only a length, which hid it. Renaming the top-level function
removes both the wrong value and the finding. Filed with the repro in
`specs/todos/2026-10-11-inline-captures-toplevel-fn-named-like-callback-param.md`; not fixed here.

The oracle (`test/test_oracle.ml`) lists the fixture in `known_divergence` with that pointer, which
is the oracle's documented route for an open bug. Remove the entry with the fix.

## Sweep

450 programs (`test/native`, `bench`, `test/snapshots/src`) at `--no-opt`, `--opt 0` and
`--opt 2`, plus the 90 programs of `examples/` and `specs/lang/golden/` at `--no-opt` and
`--opt 2`, all with the verifier on. The only contract finding is the fixture above.

A first sweep covered 0 programs, because the scratch corpus directory had been cleaned between
sessions. It printed "0 findings" and meant nothing. The sweep script now fails when it runs
fewer than 400 programs.

## Red

`test/test_codegen.ml`, group `tir_verify`: a lambda survives Defun (reported at `tir-defun` and
`tir-perceus`, not at `tir-mono`, and a `letrec` whose body is not the function is not a site),
and a shadowed local called directly (the same call as `ECallPtr` is clean, and before Defun it is
expected). Both fail without the checks.
