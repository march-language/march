# JIT: `to_string` of any List / Option / Result / tuple was an internal compiler error (fixed)

**Filed 2026-09-24** (found while triaging [[2026-09-24-jit-to-list-float]]).
**Fixed 2026-09-25.**

## Report

This program runs correctly interpreted and under `--compile` (it prints
`[3.5, 1.25, 2.]`), but `march --jit` aborted with exit 3:

```march
mod Tlf do
  needs IO.Console
  fn main(_cap_console : Cap(IO.Console)) do
    let xs = NativeArray.to_list_float(NativeArray.from_list_float([3.5, 1.25, 2.0]))
    println(to_string(xs))
  end
end
```

```
march: internal compiler error: March_tir.Llvm_calls.Ambiguous_iface_call("ambiguous
interface-method call to `Show$List.show`: 20 implementations are in scope ...")
Raised at March_tir__Llvm_calls.fail_if_unresolved_iface_method
Called from March_tir__Llvm_repl.emit_fns_fragment
Called from March_jit__Repl_jit.run_program
```

## Scope found

The bug was wider than Float lists. It covered **every `Show` of a generic
container**, on **both** JIT entry points:

| shape | `march --jit file` | JIT REPL prompt |
|---|---|---|
| `List(Float)`, `List(Int)`, `List(String)`, `List(Bool)` | ICE, `Show$List.show` | ICE |
| `List(List(Int))`, `List(Option(Int))` | ICE, `Show$List.show` | ICE |
| `Option(Int)`, `Option(Float)` | ICE, `Show$Option.show` | ICE |
| `(Int, Float)` | ICE, `Show$$Tuple2.show` | ICE |
| `Int`, `String`, ... (monomorphic `Show`) | fine | fine |
| `==` on List / Option / Result | fine (structural, not the `Eq` impl table) | — |

Interpreter and `--compile` were correct for all of them.

## Cause

Both JIT paths lower the user's code through `Lower.lower_module
~stdlib_context:<prelude decls>`, against a stdlib prelude already compiled
into a cached `.so`. For stdlib-context impls, `collect_iface_impls` ran with
`~lower_bodies:false`. The comment said "the function is already
precompiled", so it only registered the dispatch-table entry.

That holds for a **monomorphic** impl (`Show$Int.show` is in the prelude's
`.names`). It does not hold for a **generic** one: `impl Show(List(a)) when
Show(a)`, `Option(a)`, `Result(a, e)` and the tuple arities 2-5 in
`stdlib/prelude.march`. Mono emits only specialisations, and nothing inside the
prelude calls them, so no `Show$List.show*` exists in the `.so` at all. The
user fragment had no body for Mono to specialise, so the call stayed as a bare
`Show$List.show`. That name is in neither the fragment's defines nor its
externs, so `fail_if_unresolved_iface_method` fired (its candidate list came
from the lowering-time `Show.show` dispatch table, hence "20 implementations").

`--compile` never hit this because the stdlib and the user program are one
module there: every impl body is lowered and Mono specialises
`Show$List.show` at the call site.

## Fix

`lib/tir/lower.ml`: `collect_iface_impls` takes `?lower_generic`, and the
stdlib-context call passes `~lower_generic:true`. A **top-level** stdlib-context
impl whose type is generic (`TyCon (_, _ :: _)` or a tuple) now has its body
lowered into the fragment, the same as a user impl. Mono then specialises it at
this fragment's call site (`Show$List.show$…`), as the AOT pipeline does.
Monomorphic stdlib impls stay registration-only. They still come from the
`.so`, and even if lowered, `partition_fns` would classify them as externs.
Module-nested generic stdlib impls (`List`'s `Eq(List(a))` and similar) are left
alone. Their bodies name module-local helpers that this path does not lower
into a fragment. They are also not needed: `==` dispatches structurally, and a
JIT run shows it is correct.

No other caller passes `stdlib_context` (only `lib/jit/repl_jit.ml`), so
`--compile`, the interpreter and the LSP are unaffected.

## Evidence

- `test/test_jit.ml`:
  - `jit_file` / "march --jit to_string of List/Option/Result/tuple values" runs
    the report's program plus Int/String/nested lists, `Option`, `Result` and a
    tuple under `--jit`.
  - `repl_session` / "to_string of List/Option/tuple (JIT)" runs the same
    shapes at the JIT prompt, with an interpreter-mode parity control.
- With `lib/tir/lower.ml` swapped back to origin/main's copy,
  `scripts/run-tests.sh test_jit` fails exactly the two new JIT cases (the
  interpreter control passes). With the fix, all 32 cases pass.
- Manual `--jit` outputs match the interpreter byte for byte (`[a, b]`,
  `[Some(1), None]`, `(1, 2.5)`, `[3.5, 1.25, 2.]`).
