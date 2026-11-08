# `[P2]` A function from another module taken as a value fails to compile

**Logged:** 2026-10-13, found while extending the call-arity check
(`specs/progress/2026-10-12-two-arg-fn-accepted-as-curried.md`).

```march
mod LL do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    let k = List.length
    println(int_to_string(k([1, 2])))
  end
end
```

- `--check`: clean. Interpreted: prints `2`.
- `--compile`: `error: use of undefined value '@List.length'` from clang on the emitted
  `.ll`, exit 1.

A stdlib (or other-module) function used as a first-class value, rather than called
directly, is referenced in the IR by a name no function is emitted under (the direct
call path resolves it; the value path does not, or the function was pruned because no
direct call kept it alive). Start with `march query callers List.length FILE` and the
`tir-defun` / `tir-dce` dumps (`MARCH_DUMP_TXT=tir-defun`) to see whether the
reference survives defunctionalisation and the definition does not survive DCE.

## Resolved 2026-11-07

The missing edge was in monomorphization, before defunctionalization or DCE.
`Mono.rewrite_calls` kept functions passed as call arguments reachable, but ignored
`EAtom` references such as the RHS of `let k = List.length`. Polymorphic functions
are not initial worklist roots, so mono emitted specialized `List.length$...`
variants for other callers while dropping the generic `List.length` referenced
by the value. The native closure wrapper then called an undefined symbol.

`lib/tir/mono.ml` now discovers non-shadowed function-value atoms using the same
worklist helper as function-valued arguments. It retains the generic body because
a let-generalized function can be called at multiple types. Local parameters and
bindings remain protected by the existing lexical-shadowing set.

Regression: `test/test_codegen.ml`, group `module_function_values`, binds
`List.length` once and invokes it on both integer and string lists, asserting
native output `2\n3`. The test failed before the fix with clang's undefined
`@List.length` error and passes after it. Initial `scripts/triage.sh` reproduced
interpreter output `2` versus the native compile failure. The compiled
`bench/list_ops.march` benchmark (`--opt 2`) still prints `333333666666`.

Broader validation: the 723-case quick codegen run encountered 69 missing-compiler
failures during an overlapping rebuild and one incomplete staged-stdlib failure.
After finishing builds and pointing MARCH_STDLIB at the source tree, all 81 cases
in the affected groups passed, including the full 410-fixture LLVM validity corpus
and its debug-info check. The initial failed invocation is not counted as passing.
