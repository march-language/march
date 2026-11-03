# Matching a payload atom (`:count(x)`) is an internal compiler error when compiled

Filed 2026-10-12. Found by compiling `specs/lang/types/accept/` in the TIR verifier sweep
(`specs/progress/2026-10-12-verifier-leak-sweep.md`).

`specs/lang/types/accept/t12_atom_payload_and_name_erasure.march` runs interpreted and prints
`no payload`, `no payload`, `42`. `--compile` fails:

```
march: internal compiler error: Failure("LLVM Llvm_ctx.emit: constructor pattern
count($f..) destructures a non-pointer scrutinee — type-incorrect TIR reached codegen ...")
```

`describe(a : Atom)` matches `:count(x)`. In `Llvm_case`, an `Atom` scrutinee is never a
pointer (`TCon ("Atom", []) -> false`, "atoms are i64 scalars"). But a payload atom is lowered
to `alloc count(42)`, which is a heap cell. So a constructor arm with binders on an `Atom`
scrutinee has no representation codegen can read. After inlining, the scrutinee is even a
literal (`case :red of count(..)`).

This needs a representation decision before it can be fixed. One option is a payload atom as a
boxed cell plus a pointer test on `Atom` scrutinees; another is to reject payload-atom patterns
in compiled code with a diagnostic. Either way it is not a small fix.

The verifier did not flag the TIR. Check 2's case-arity rule needs the scrutinee's variant, and
`Atom` has none. A check 4 (representation invariants) rule, "a constructor arm with binders
needs a pointer-represented scrutinee", would catch it. That belongs to the verifier's owner.
