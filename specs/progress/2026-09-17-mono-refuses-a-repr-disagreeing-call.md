# Mono refuses a call whose caller and callee disagree about the representation

Landed 2026-09-17. Step 2 of
`specs/todos/2026-08-01-lazy-stdlib-loading-boxed-vs-niche-representation-mismatch.md`,
which had been **deferred on 2026-08-09 with a stated architectural blocker**.
The blocker is refuted; see below.

## The class bug

A stdlib module outside `Stdlib_manifest.stdlib_file_list` is loaded to extract
export SHAPES only — its body never goes through inference in the caller's
context. Monomorphization then reaches a call to a generic
`Option`/`Result`-returning function with the callee's return still an
unresolved tvar, cannot specialize, and falls back to the generic **boxed**
body. The caller, compiled at a concrete niche-eligible type, reads the box's
bits as the payload. Wrong value, no crash, no diagnostic, compiled only.

Step 1 (2026-08-03) contained it with an exhaustiveness test over the manifest.
That closes the realistic reintroduction path but not the class.

## The 2026-08-09 blocker, and why it no longer holds

> the disagreement predicate is `repr_of_ty(caller) <> repr_of_ty(callee)` … but
> `repr_of_ty` is only sound when passed the real `collision_set` … computed at
> **codegen** time … **mono runs before it exists** and has no handle on it.

Three things make that false today:

1. **`Collision_set.compute` is a pure function of `Tir.type_def list`** — it
   takes nothing from codegen. Four passes already call it directly on
   `m.tm_types` (`drop.ml`, `kind.ml`, `perceus.ml`, `contract_pipeline.ml`),
   and `lower.ml` computes one *before Pass 1*, with a doc comment requiring
   that early set to agree with the later one.
2. **Mono does not touch `tm_types`.** It returns `{ m with tm_fns = … }`, so a
   table built at its entry is the same table later passes build.
3. **The one pass that does add types runs after mono and cannot change the
   set.** `defun` appends `$Clo_<fn>$<uid>` closure structs; a `$`-prefixed name
   cannot collide with a user or builtin type, nor make two existing names
   collide.

The 2026-09-10 type-kinds refactor also replaced the process-global repr
registry with a `Kind.table` value, so `Kind.of_module m` now gives mono
everything in one call.

## The predicate, measured before it became an error

The todo is emphatic that *"specialization failed"* is NOT the error condition —
`g44_crdt_convergence`'s `CRDT.ORSet.union_tags` takes the fallback and is
byte-identical to its interpreted output. The predicate has to be the
disagreement itself. Instrumented under `MARCH_MONO_REPR_REPORT=1` and swept:

| corpus | programs | fallback calls | `disagree=true` |
|---|---|---|---|
| `specs/lang/golden` | 47 | 570 | **0** |
| `bench` + `test/native` | 269 | 1,634 | **0** |
| the `ConsistentHash` repro, module made lazy | 1 | 8 | **1** |

The single hit is exactly the miscompiling call:

```
MONOREPR  ConsistentHash.get  caller_ret=TCon(Option,[TInt])
                              callee_ret=TCon(Option,[TVar(a)])
                              caller_repr=Niche(tagged)  callee_repr=Boxed  disagree=true
```

2,204 fallbacks across 316 programs, zero false positives. `MARCH_MONO_REPR_REPORT=1`
is kept as a debugging aid — it is how this was measured and how the next
disagreement should be triaged.

## The error

Raised as a dedicated `Mono.Repr_disagreement`, not `Failure`. A `Failure`
escaping the pipeline reaches bin/main.ml's `| exn ->` handler, which prints
*"internal compiler error … This is a compiler bug, not a problem with your
program"* plus an OCaml backtrace — the opposite of the truth here, where the
program or the manifest is exactly what needs changing. The driver renders it
as one `march: error:` line with rc=1.

The message names the call, both return types, both representations, what would
happen at run time, and the fix (add the file to `stdlib_file_list`).

## Verification

- **REJECT witness** — the todo's own acceptance criterion, and the point of the
  whole exercise: with `consistent_hash.march` moved from `stdlib_file_list` to
  `lazily_loaded_allowlist`, the repro becomes a compile error instead of a
  garbage value. Reproduce by making that one-line manifest edit.
- **ACCEPT** — `test/native/lazy_niche.march`, the fixture that exists to keep
  the lazy path alive, still compiles and still prints `42 / 99`. The predicate
  does not fire on it.
- A non-vacuity guard in `test/test_kind.ml`: `Option(Int)` classifies as a
  niche and `Option('a)` as boxed, so the check has something to fire on. If
  that ever stops holding the check would silently stop catching anything.
- Full suite.

## What this does NOT fix

Step 3 (giving lazily-loaded modules real inference) is still open and still the
better end state: this makes the failure VISIBLE, not absent.

And separately — found while building the witness — the `ConsistentHash` repro
**miscompiles on `origin/main` today even with the module eagerly loaded**,
interpreted `SOME 42` vs compiled SIGBUS, with zero repr disagreements
reported. That is a different mechanism and has its own todo.
